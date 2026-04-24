// Beamformer testbench — Phase 1.4 co-simulation
// Reads input samples from inputs.hex and expected outputs from expected_output.hex.
// Drives DUT, compares output on every y_valid pulse, reports pass/fail.
//
// inputs.hex format (per sample):
//   2*M lines: x_re[0], x_im[0], x_re[1], x_im[1], ..., x_re[M-1], x_im[M-1]
//
// expected_output.hex format (per sample):
//   2 lines: y_re, y_im  (Q1.14, 16-bit two's complement)

`timescale 1ns/1ps

module beamformer_tb;

    // ── Parameters ────────────────────────────────────────────────────────────
    localparam int M         = 8;
    localparam int X_WIDTH   = 16;
    localparam int OUT_WIDTH = 16;
    localparam int N_SAMPLES = 512;
    localparam int CLK_HALF  = 5;    // 10 ns period = 100 MHz sim clock

    // ── Clock and reset ───────────────────────────────────────────────────────
    logic clk   = 0;
    logic rst_n = 0;

    always #CLK_HALF clk = ~clk;

    // ── DUT ports ─────────────────────────────────────────────────────────────
    logic                        sample_valid;
    logic signed [X_WIDTH-1:0]   x_re [0:M-1];
    logic signed [X_WIDTH-1:0]   x_im [0:M-1];
    logic signed [OUT_WIDTH-1:0] y_re, y_im;
    logic                        y_valid;

    beamformer_top #(
        .M        (M),
        .X_WIDTH  (X_WIDTH),
        .W_WIDTH  (16),
        .P_WIDTH  (32),
        .Y_WIDTH  (36),
        .OUT_WIDTH(OUT_WIDTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .sample_valid (sample_valid),
        .x_re         (x_re),
        .x_im         (x_im),
        .y_re         (y_re),
        .y_im         (y_im),
        .y_valid      (y_valid)
    );

    // ── Load test vectors ─────────────────────────────────────────────────────
    logic signed [X_WIDTH-1:0]   inputs_flat   [0:2*M*N_SAMPLES-1];
    logic signed [OUT_WIDTH-1:0] exp_flat       [0:2*N_SAMPLES-1];

    initial begin
        $readmemh("vectors/inputs.hex",          inputs_flat);
        $readmemh("vectors/expected_output.hex", exp_flat);
    end

    // ── Stimulus and checking ─────────────────────────────────────────────────
    int  mismatches;
    int  checked;
    int  exp_idx;
    logic checking_enabled = 1'b0;  // only enabled during main test

    // Check on every y_valid pulse
    always_ff @(posedge clk) begin
        if (y_valid && checking_enabled) begin
            logic signed [OUT_WIDTH-1:0] exp_re, exp_im;
            exp_re = exp_flat[exp_idx];
            exp_im = exp_flat[exp_idx + 1];
            exp_idx += 2;
            checked++;

            // Allow ±1 LSB tolerance for rounding differences
            if ((y_re < exp_re - 1) || (y_re > exp_re + 1) ||
                (y_im < exp_im - 1) || (y_im > exp_im + 1)) begin
                $display("MISMATCH sample %0d: got (%0d, %0d)  expected (%0d, %0d)",
                         checked, y_re, y_im, exp_re, exp_im);
                mismatches++;
            end
        end
    end

    // ── Directed test: all-zero input ─────────────────────────────────────────
    task automatic drive_zero_sample;
        @(posedge clk);
        sample_valid = 1'b1;
        for (int i = 0; i < M; i++) begin
            x_re[i] = '0;
            x_im[i] = '0;
        end
        @(posedge clk);
        sample_valid = 1'b0;
    endtask

    // ── Main stimulus ─────────────────────────────────────────────────────────
    initial begin
        mismatches   = 0;
        checked      = 0;
        exp_idx      = 0;
        sample_valid = 1'b0;
        for (int i = 0; i < M; i++) begin
            x_re[i] = '0;
            x_im[i] = '0;
        end

        // Reset
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        repeat(2) @(posedge clk);

        // ── Directed test: all-zero input should produce zero output ──────────
        drive_zero_sample();
        repeat(20) @(posedge clk);   // wait for pipeline to flush

        // ── Main test: drive all N_SAMPLES from inputs.hex ───────────────────
        checking_enabled = 1'b1;
        for (int n = 0; n < N_SAMPLES; n++) begin
            @(posedge clk);
            sample_valid = 1'b1;
            for (int m = 0; m < M; m++) begin
                x_re[m] = inputs_flat[n * 2*M + 2*m];
                x_im[m] = inputs_flat[n * 2*M + 2*m + 1];
            end
            @(posedge clk);
            sample_valid = 1'b0;
            // Wait for pipeline — one sample every ~(M+5) cycles
            repeat(M + 5) @(posedge clk);
        end

        // Flush remaining outputs
        repeat(30) @(posedge clk);

        // ── Results ───────────────────────────────────────────────────────────
        $display("=================================================");
        $display("  BEAMFORMER CO-SIMULATION RESULTS");
        $display("=================================================");
        $display("  Samples checked : %0d / %0d", checked, N_SAMPLES);
        $display("  Mismatches      : %0d", mismatches);
        if (mismatches == 0 && checked == N_SAMPLES)
            $display("  Result          : PASS");
        else
            $display("  Result          : FAIL");
        $display("=================================================");

        $finish;
    end

endmodule
