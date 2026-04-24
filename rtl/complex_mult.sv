// Complex multiplier — computes conj(a) * b
// Stage 1: four real multiplies
// Stage 2: two adds/subtracts → product real and imaginary parts
// Two pipeline stages ensure DSP48 inference in Vivado.
//
// Fixed-point formats (Phase 1.2 §9):
//   a, b inputs : Q1.15  (WL=16, signed)
//   p output    : Q2.30  (WL=32, signed) — product of two Q1.15 values

`timescale 1ns/1ps

module complex_mult #(
    parameter int IN_WIDTH  = 16,   // width of each input component
    parameter int OUT_WIDTH = 32    // width of each output component
) (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic signed [IN_WIDTH-1:0]  a_re,   // real part of a
    input  logic signed [IN_WIDTH-1:0]  a_im,   // imaginary part of a
    input  logic signed [IN_WIDTH-1:0]  b_re,   // real part of b
    input  logic signed [IN_WIDTH-1:0]  b_im,   // imaginary part of b
    input  logic                        valid_in,

    output logic signed [OUT_WIDTH-1:0] p_re,   // real part of conj(a)*b
    output logic signed [OUT_WIDTH-1:0] p_im,   // imaginary part of conj(a)*b
    output logic                        valid_out
);

    // conj(a) * b = (a_re - j*a_im)(b_re + j*b_im)
    //             = (a_re*b_re + a_im*b_im) + j(a_re*b_im - a_im*b_re)

    // Stage 1 registers — four partial products
    logic signed [2*IN_WIDTH-1:0] pp_rr, pp_ii, pp_ri, pp_ir;
    logic                         valid_s1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pp_rr    <= '0;
            pp_ii    <= '0;
            pp_ri    <= '0;
            pp_ir    <= '0;
            valid_s1 <= 1'b0;
        end else begin
            pp_rr    <= a_re * b_re;
            pp_ii    <= a_im * b_im;
            pp_ri    <= a_re * b_im;
            pp_ir    <= a_im * b_re;
            valid_s1 <= valid_in;
        end
    end

    // Stage 2 registers — sum/difference to form complex product
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_re      <= '0;
            p_im      <= '0;
            valid_out <= 1'b0;
        end else begin
            p_re      <= OUT_WIDTH'(pp_rr + pp_ii);
            p_im      <= OUT_WIDTH'(pp_ri - pp_ir);
            valid_out <= valid_s1;
        end
    end

endmodule
