// Beamformer top — delay-and-sum beamformer, M antennas, fixed weights.
//
// Pipeline:
//   Cycle 0        : x[m] presented, weight_rom outputs registered weights
//   Cycle 1-2      : complex_mult stage 1 (partial products)
//   Cycle 3        : complex_mult stage 2 (products p[m] valid)
//   Cycle 3 onward : products fed one-per-cycle to complex_accumulator
//   Cycle 3+M      : accumulator outputs y — y_valid pulses high for one cycle
//
// Input samples for all M antennas are presented simultaneously (one snapshot
// per sample_valid pulse). The top level serialises them into the accumulator.

`timescale 1ns/1ps

module beamformer_top #(
    parameter int M        = 8,    // number of antennas
    parameter int X_WIDTH  = 16,   // input sample width  (Q1.15)
    parameter int W_WIDTH  = 16,   // weight width        (Q1.15)
    parameter int P_WIDTH  = 32,   // multiplier output   (Q2.30)
    parameter int Y_WIDTH  = 36,   // accumulator output  (Q4.31)
    parameter int OUT_WIDTH = 16   // final output        (Q1.14, saturated)
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // Input: one snapshot of M antenna samples
    input  logic                          sample_valid,
    input  logic signed [X_WIDTH-1:0]     x_re [0:M-1],
    input  logic signed [X_WIDTH-1:0]     x_im [0:M-1],

    // Output: beamformed scalar sample
    output logic signed [OUT_WIDTH-1:0]   y_re,
    output logic signed [OUT_WIDTH-1:0]   y_im,
    output logic                          y_valid
);

    // ── Weight ROM ────────────────────────────────────────────────────────────
    logic signed [W_WIDTH-1:0] w_re [0:M-1];
    logic signed [W_WIDTH-1:0] w_im [0:M-1];

    weight_rom #(.M(M), .WIDTH(W_WIDTH)) u_rom (
        .clk   (clk),
        .rst_n (rst_n),
        .w_re  (w_re),
        .w_im  (w_im)
    );

    // ── M parallel complex multipliers ───────────────────────────────────────
    logic signed [P_WIDTH-1:0] p_re [0:M-1];
    logic signed [P_WIDTH-1:0] p_im [0:M-1];
    logic                      p_valid [0:M-1];

    // Register inputs one cycle to align with weight_rom read latency
    logic signed [X_WIDTH-1:0] x_re_r [0:M-1];
    logic signed [X_WIDTH-1:0] x_im_r [0:M-1];
    logic                      sample_valid_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_valid_r <= 1'b0;
            for (int i = 0; i < M; i++) begin
                x_re_r[i] <= '0;
                x_im_r[i] <= '0;
            end
        end else begin
            sample_valid_r <= sample_valid;
            for (int i = 0; i < M; i++) begin
                x_re_r[i] <= x_re[i];
                x_im_r[i] <= x_im[i];
            end
        end
    end

    genvar g;
    generate
        for (g = 0; g < M; g++) begin : gen_mult
            complex_mult #(
                .IN_WIDTH  (X_WIDTH),
                .OUT_WIDTH (P_WIDTH)
            ) u_mult (
                .clk       (clk),
                .rst_n     (rst_n),
                .a_re      (w_re[g]),
                .a_im      (w_im[g]),
                .b_re      (x_re_r[g]),
                .b_im      (x_im_r[g]),
                .valid_in  (sample_valid_r),
                .p_re      (p_re[g]),
                .p_im      (p_im[g]),
                .valid_out (p_valid[g])
            );
        end
    endgenerate

    // ── Serialise M products into the accumulator ─────────────────────────────
    // When p_valid[0] fires, all M products are ready simultaneously.
    // We feed them one per cycle using a mux driven by a counter.

    logic [$clog2(M)-1:0] ser_cnt;
    logic                 ser_active;
    logic signed [P_WIDTH-1:0] acc_re_in, acc_im_in;
    logic                      acc_valid_in;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ser_cnt    <= '0;
            ser_active <= 1'b0;
        end else begin
            if (p_valid[0] && !ser_active) begin
                ser_active <= 1'b1;
                ser_cnt    <= '0;
            end else if (ser_active) begin
                if (ser_cnt == $clog2(M)'(M - 1)) begin
                    ser_active <= 1'b0;
                    ser_cnt    <= '0;
                end else begin
                    ser_cnt <= ser_cnt + 1'b1;
                end
            end
        end
    end

    always_comb begin
        acc_re_in    = p_re[ser_cnt];
        acc_im_in    = p_im[ser_cnt];
        acc_valid_in = ser_active;
    end

    // ── Complex accumulator ───────────────────────────────────────────────────
    logic signed [Y_WIDTH-1:0] acc_re_out, acc_im_out;
    logic                      acc_valid_out;

    complex_accumulator #(
        .M         (M),
        .IN_WIDTH  (P_WIDTH),
        .OUT_WIDTH (Y_WIDTH)
    ) u_acc (
        .clk         (clk),
        .rst_n       (rst_n),
        .data_re_in  (acc_re_in),
        .data_im_in  (acc_im_in),
        .valid_in    (acc_valid_in),
        .data_re_out (acc_re_out),
        .data_im_out (acc_im_out),
        .valid_out   (acc_valid_out)
    );

    // ── Output: truncate accumulator to OUT_WIDTH with saturation ─────────────
    // Q4.31 → Q1.14: drop 17 LSBs (right shift), keep upper OUT_WIDTH bits.
    // Saturate if the value exceeds Q1.14 range [-2, +2).

    localparam int SHIFT     = 17;   // FL_acc - FL_out = 31 - 14
    localparam int SAT_MAX   =  (1 << (OUT_WIDTH-1)) - 1;  //  32767
    localparam int SAT_MIN   = -(1 << (OUT_WIDTH-1));       // -32768

    function automatic logic signed [OUT_WIDTH-1:0] saturate(
        input logic signed [Y_WIDTH-1:0] x
    );
        logic signed [Y_WIDTH-1:0] shifted;
        shifted = x >>> SHIFT;
        if (shifted > SAT_MAX)       return SAT_MAX;
        else if (shifted < SAT_MIN)  return SAT_MIN;
        else                         return OUT_WIDTH'(shifted);
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_re    <= '0;
            y_im    <= '0;
            y_valid <= 1'b0;
        end else begin
            y_valid <= acc_valid_out;
            if (acc_valid_out) begin
                y_re <= saturate(acc_re_out);
                y_im <= saturate(acc_im_out);
            end
        end
    end

endmodule
