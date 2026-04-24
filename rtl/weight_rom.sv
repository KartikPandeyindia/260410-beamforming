// Weight ROM — stores M complex weights initialised from weights.hex.
// Delivers all M weights in parallel on registered outputs.
// weights.hex format: one 16-bit two's-complement value per line,
//   real part of w[0], imag part of w[0], real part of w[1], ... (2*M lines)

`timescale 1ns/1ps

module weight_rom #(
    parameter int M     = 8,    // number of antennas / weights
    parameter int WIDTH = 16    // word length per component (Q1.15)
) (
    input  logic clk,
    input  logic rst_n,

    output logic signed [WIDTH-1:0] w_re [0:M-1],
    output logic signed [WIDTH-1:0] w_im [0:M-1]
);

    // Flat ROM: indices 0,1 = w[0] re/im; 2,3 = w[1] re/im; ...
    logic signed [WIDTH-1:0] rom [0:2*M-1];

    initial begin
        $readmemh("vectors/weights.hex", rom);
    end

    // Register outputs for one-cycle read latency (matches DSP pipeline entry)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < M; i++) begin
                w_re[i] <= '0;
                w_im[i] <= '0;
            end
        end else begin
            for (int i = 0; i < M; i++) begin
                w_re[i] <= rom[2*i];
                w_im[i] <= rom[2*i + 1];
            end
        end
    end

endmodule
