// Complex accumulator — sums M sequential complex inputs into one output.
// Counts M valid cycles, registers the sum, then resets for the next sample.
//
// Fixed-point formats (Phase 1.2 §9):
//   data_in  : Q2.30  (WL=32) — multiplier output
//   data_out : Q4.31  (WL=36) — accumulator (3 guard bits for M=8)

`timescale 1ns/1ps

module complex_accumulator #(
    parameter int M        = 8,    // number of inputs to accumulate
    parameter int IN_WIDTH = 32,   // width of each input component
    parameter int OUT_WIDTH = 36   // width of each output component
) (
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic signed [IN_WIDTH-1:0] data_re_in,
    input  logic signed [IN_WIDTH-1:0] data_im_in,
    input  logic                       valid_in,

    output logic signed [OUT_WIDTH-1:0] data_re_out,
    output logic signed [OUT_WIDTH-1:0] data_im_out,
    output logic                        valid_out
);

    localparam int CNT_WIDTH = $clog2(M);

    logic signed [OUT_WIDTH-1:0] acc_re, acc_im;
    logic        [CNT_WIDTH-1:0] count;
    logic                        valid_out_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_re      <= '0;
            acc_im      <= '0;
            count       <= '0;
            data_re_out <= '0;
            data_im_out <= '0;
            valid_out   <= 1'b0;
        end else begin
            valid_out <= 1'b0;

            if (valid_in) begin
                if (count == CNT_WIDTH'(M - 1)) begin
                    // Last antenna — register output and reset accumulator
                    data_re_out <= acc_re + OUT_WIDTH'(data_re_in);
                    data_im_out <= acc_im + OUT_WIDTH'(data_im_in);
                    valid_out   <= 1'b1;
                    acc_re      <= '0;
                    acc_im      <= '0;
                    count       <= '0;
                end else begin
                    acc_re <= acc_re + OUT_WIDTH'(data_re_in);
                    acc_im <= acc_im + OUT_WIDTH'(data_im_in);
                    count  <= count + 1'b1;
                end
            end
        end
    end

endmodule
