% =========================================================================
% Phase 1.2 — Fixed-Point Analysis (no Fixed-Point Designer toolbox)
% Imports parameters and golden reference from algo_sim.m
% Determines minimum word lengths for RTL implementation
% Exports test vectors for the SystemVerilog testbench
%
% Sections:
%   1. Import Phase 1.1
%   2. Fixed-point format definitions
%   3. Scale and quantize signals
%   4. Fixed-point beamformer
%   5. Fixed-point radiation pattern
%   6. Metrics comparison
%   7. Word-length sweep
%   8. Plots
%   9. Export test vectors
%  10. Summary table
% =========================================================================

if exist('command_line_output.txt', 'file'),  delete('command_line_output.txt');  end
diary('command_line_output.txt');  % saved in matlab/ alongside the script
run('algo_sim.m');
close all;

fprintf('\n=================================================\n');
fprintf('  PHASE 1.2 — FIXED-POINT ANALYSIS\n');
fprintf('=================================================\n');

% -------------------------------------------------------------------------
% 2. FIXED-POINT FORMAT DEFINITIONS  (PLAN.md §7.1)
% -------------------------------------------------------------------------
WL_x    = 16;  FL_x    = 15;   % Input samples:     Q1.15
WL_w    = 16;  FL_w    = 15;   % Weights:           Q1.15
WL_prod = 32;  FL_prod = 30;   % Multiplier output: Q2.30
WL_acc  = 36;  FL_acc  = 31;   % Accumulator:       Q5.31
WL_out  = 16;  FL_out  = 14;   % Output:            Q2.14

% -------------------------------------------------------------------------
% 3. SCALE AND QUANTIZE SIGNALS
% -------------------------------------------------------------------------
X_peak   = max(abs([real(X(:)); imag(X(:))]));
X_scale  = (1 - 2^(-WL_x)) / X_peak;
X_scaled = X * X_scale;

X_qd = quantize_fp(X_scaled, WL_x, FL_x);
w_qd = quantize_fp(w,        WL_w, FL_w);

fprintf('\n  Input peak           : %.4f  ->  scaled to %.4f\n', ...
        X_peak, X_peak * X_scale);
fprintf('  Scale factor         : %.6f  (%.2f dB)\n', ...
        X_scale, 20*log10(X_scale));

% -------------------------------------------------------------------------
% 4. FIXED-POINT BEAMFORMER
% -------------------------------------------------------------------------
y_fixed_dbl = fpBeamformer(w_qd, X_qd, WL_out, FL_out);

y_ref = w' * X_scaled;

% -------------------------------------------------------------------------
% 5. FIXED-POINT RADIATION PATTERN
% -------------------------------------------------------------------------
AF_fixed = zeros(1, length(phi_deg));
for k = 1:length(phi_deg)
    a_phi        = steeringVector(phi_deg(k), M, d_over_lam);
    AF_fixed(k)  = abs(w_qd' * a_phi);
end
AF_fixed_norm = AF_fixed / max(AF_fixed);
AF_fixed_dB   = 20 * log10(AF_fixed_norm + 1e-12);

% -------------------------------------------------------------------------
% 6. METRICS COMPARISON
% -------------------------------------------------------------------------
[~, int_idx] = min(abs(phi_deg - theta_int));

mask        = AF_dB > -40;   % ignore deep nulls where log subtraction is meaningless
peak_dev_dB = max(abs(AF_dB(mask) - AF_fixed_dB(mask)));
null_dev_dB = abs(AF_dB(int_idx) - AF_fixed_dB(int_idx));
bw3_float   = beamwidth3dB(phi_deg, AF_dB);
bw3_fixed   = beamwidth3dB(phi_deg, AF_fixed_dB);

quant_err  = y_fixed_dbl - y_ref;
sig_pwr    = mean(abs(y_ref).^2);
qnoise_pwr = mean(abs(quant_err).^2);
SQNR_dB    = 10 * log10(sig_pwr / qnoise_pwr);

gain_sig_fp  = abs(w_qd' * a_sig)^2;
gain_int_fp  = abs(w_qd' * a_int)^2;
P_sig_fp     = gain_sig_fp * sig_power;
P_int_fp     = gain_int_fp * int_power;
P_n_fp       = noise_sigma^2 * norm(w_qd)^2;
SINR_fp_dB   = 10 * log10(P_sig_fp / (P_int_fp + P_n_fp));

fprintf('\n--- Radiation pattern (WL_w = %d bit) ---------------\n', WL_w);
fprintf('  Max pattern deviation : %.4f dB  (tolerance < 0.5 dB)\n', peak_dev_dB);
fprintf('  Null depth deviation  : %.4f dB  (tolerance < 5.0 dB)\n', null_dev_dB);
fprintf('  3 dB BW  float        : %.3f deg\n', bw3_float);
fprintf('  3 dB BW  fixed        : %.3f deg\n', bw3_fixed);
fprintf('  BW deviation          : %.4f deg\n', abs(bw3_fixed - bw3_float));
fprintf('\n--- Beamformer output --------------------------------\n');
fprintf('  SQNR                  : %.2f dB\n', SQNR_dB);
fprintf('  Output SINR (float)   : %.2f dB\n', SINR_out_dB);
fprintf('  Output SINR (fixed)   : %.2f dB\n', SINR_fp_dB);
fprintf('  SINR degradation      : %.2f dB\n', SINR_out_dB - SINR_fp_dB);

% -------------------------------------------------------------------------
% 7. WORD-LENGTH SWEEP
% -------------------------------------------------------------------------
WL_range  = 6:2:24;
peak_devs = zeros(size(WL_range));
null_devs = zeros(size(WL_range));
bw_devs   = zeros(size(WL_range));

for idx = 1:length(WL_range)
    wl   = WL_range(idx);
    fl   = wl - 1;
    w_sw = quantize_fp(w, wl, fl);

    AF_sw = zeros(1, length(phi_deg));
    for k = 1:length(phi_deg)
        a_phi    = steeringVector(phi_deg(k), M, d_over_lam);
        AF_sw(k) = abs(w_sw' * a_phi);
    end
    AF_sw_norm = AF_sw / max(AF_sw);
    AF_sw_dB   = 20 * log10(AF_sw_norm + 1e-12);

    mask_sw        = AF_dB > -40;
    peak_devs(idx) = max(abs(AF_dB(mask_sw) - AF_sw_dB(mask_sw)));
    null_devs(idx) = abs(AF_dB(int_idx) - AF_sw_dB(int_idx));
    bw_devs(idx)   = abs(beamwidth3dB(phi_deg, AF_dB) - beamwidth3dB(phi_deg, AF_sw_dB));
end

fprintf('\n--- Word-length sweep --------------------------------\n');
fprintf('  WL | Peak dev (dB) | Null dev (dB) | BW dev (deg)\n');
fprintf('  ---|---------------|---------------|-------------\n');
for idx = 1:length(WL_range)
    mark = '';
    if WL_range(idx) == WL_w,  mark = '  <- selected';  end
    fprintf('  %2d | %13.4f | %13.4f | %12.4f%s\n', ...
            WL_range(idx), peak_devs(idx), null_devs(idx), bw_devs(idx), mark);
end

% -------------------------------------------------------------------------
% 8. PLOTS
% -------------------------------------------------------------------------

figure('Name', 'FP1.2: Radiation Pattern Comparison', 'NumberTitle', 'off');
plot(phi_deg, AF_dB,       'b-',  'LineWidth', 1.5); hold on;
plot(phi_deg, AF_fixed_dB, 'r--', 'LineWidth', 1.2);
xline(theta_sig, 'g:', 'LineWidth', 1.0, ...
      'Label', sprintf('Target %.0f deg', theta_sig), ...
      'LabelVerticalAlignment', 'bottom');
xline(theta_int, 'm:', 'LineWidth', 1.0, ...
      'Label', sprintf('Interferer %.0f deg', theta_int), ...
      'LabelVerticalAlignment', 'bottom');
hold off;
xlim([-90 90]);  ylim([-60 5]);
xlabel('Angle (degrees)');  ylabel('Normalised array gain (dB)');
title(sprintf('Radiation pattern — float vs fixed-point (WL=%d, FL=%d)', WL_w, FL_w));
legend('Floating-point', sprintf('Fixed Q1.%d', FL_w), 'Location', 'southeast');
grid on;  grid minor;

figure('Name', 'FP1.2: Pattern Deviation', 'NumberTitle', 'off');
plot(phi_deg, AF_dB - AF_fixed_dB, 'r-', 'LineWidth', 1.2);
yline( 0.5, 'k--', 'LineWidth', 0.8, 'Label', '+0.5 dB');
yline(-0.5, 'k--', 'LineWidth', 0.8, 'Label', '-0.5 dB');
xlim([-90 90]);
xlabel('Angle (degrees)');  ylabel('Float - Fixed (dB)');
title(sprintf('Pattern deviation  (max = %.4f dB)', peak_dev_dB));
grid on;

figure('Name', 'FP1.2: Word-Length Sweep', 'NumberTitle', 'off');

subplot(2,1,1);
semilogy(WL_range, peak_devs, 'bs-', 'LineWidth', 1.5, 'MarkerSize', 6); hold on;
semilogy(WL_range, null_devs, 'ro-', 'LineWidth', 1.5, 'MarkerSize', 6);
xline(WL_w, 'g--', 'LineWidth', 1.2, 'Label', sprintf('WL=%d', WL_w));
yline(0.5,  'k:',  'LineWidth', 0.8, 'Label', '0.5 dB');
hold off;
xlabel('Weight word length (bits)');  ylabel('Deviation (dB)');
title('Pattern degradation vs weight word length');
legend('Peak deviation', 'Null depth deviation', 'Location', 'northeast');
grid on;

subplot(2,1,2);
plot(WL_range, bw_devs, 'ms-', 'LineWidth', 1.5, 'MarkerSize', 6);
xline(WL_w, 'g--', 'LineWidth', 1.2, 'Label', sprintf('WL=%d', WL_w));
yline(0.1,  'k:',  'LineWidth', 0.8, 'Label', '0.1 deg');
xlabel('Weight word length (bits)');  ylabel('BW deviation (deg)');
title('3 dB beamwidth deviation vs weight word length');
grid on;

figure('Name', 'FP1.2: Output Comparison', 'NumberTitle', 'off');
n_plot = 80;

subplot(2,1,1);
plot(0:n_plot-1, real(y_ref(1:n_plot)),       'b-',  'LineWidth', 1.0); hold on;
plot(0:n_plot-1, real(y_fixed_dbl(1:n_plot)), 'r--', 'LineWidth', 1.0);
hold off;
xlabel('Sample index');  ylabel('Amplitude');
title(sprintf('Output real part  (SQNR = %.1f dB)', SQNR_dB));
legend('Float ref', sprintf('Fixed Q%d.%d', WL_out-FL_out-1, FL_out));
grid on;

subplot(2,1,2);
plot(0:n_plot-1, imag(y_ref(1:n_plot)),       'b-',  'LineWidth', 1.0); hold on;
plot(0:n_plot-1, imag(y_fixed_dbl(1:n_plot)), 'r--', 'LineWidth', 1.0);
hold off;
xlabel('Sample index');  ylabel('Amplitude');
title('Output imaginary part');
legend('Float ref', sprintf('Fixed Q%d.%d', WL_out-FL_out-1, FL_out));
grid on;

figure('Name', 'FP1.2: Quantisation Error', 'NumberTitle', 'off');

subplot(2,1,1);
plot(real(quant_err), 'r-', 'LineWidth', 0.8);
xlabel('Sample index');  ylabel('Error');
title('Quantisation error — real part');
grid on;

subplot(2,1,2);
plot(imag(quant_err), 'r-', 'LineWidth', 0.8);
xlabel('Sample index');  ylabel('Error');
title('Quantisation error — imaginary part');
grid on;

% Save all figures
figs = findall(0, 'Type', 'figure');
for k = 1:length(figs)
    fname = strrep(figs(k).Name, ' ', '_');
    fname = strrep(fname, ':', '');
    saveas(figs(k), fullfile('..', 'plots', [fname '.png']));
end

% -------------------------------------------------------------------------
% 9. EXPORT TEST VECTORS
% -------------------------------------------------------------------------
vec_dir = fullfile('..', 'vectors');
if ~exist(vec_dir, 'dir'),  mkdir(vec_dir);  end

fid = fopen(fullfile(vec_dir, 'weights.hex'), 'w');
for m = 1:M
    fprintf(fid, '%s\n', to_hex2c(real(w_qd(m)), WL_w, FL_w));
    fprintf(fid, '%s\n', to_hex2c(imag(w_qd(m)), WL_w, FL_w));
end
fclose(fid);

fid = fopen(fullfile(vec_dir, 'inputs.hex'), 'w');
for n = 1:N_samples
    for m = 1:M
        fprintf(fid, '%s\n', to_hex2c(real(X_qd(m,n)), WL_x, FL_x));
        fprintf(fid, '%s\n', to_hex2c(imag(X_qd(m,n)), WL_x, FL_x));
    end
end
fclose(fid);

fid = fopen(fullfile(vec_dir, 'expected_output.hex'), 'w');
for n = 1:N_samples
    fprintf(fid, '%s\n', to_hex2c(real(y_fixed_dbl(n)), WL_out, FL_out));
    fprintf(fid, '%s\n', to_hex2c(imag(y_fixed_dbl(n)), WL_out, FL_out));
end
fclose(fid);

fprintf('\n  Vectors written to %s/\n', vec_dir);
fprintf('    weights.hex         : %d lines (%d complex weights)\n', 2*M, M);
fprintf('    inputs.hex          : %d lines (%d ant x %d samp x 2)\n', ...
        2*M*N_samples, M, N_samples);
fprintf('    expected_output.hex : %d lines (%d complex samples)\n', ...
        2*N_samples, N_samples);

% -------------------------------------------------------------------------
% 10. SUMMARY TABLE
% -------------------------------------------------------------------------
fprintf('\n=================================================\n');
fprintf('  PHASE 1.2 SUMMARY — LOCKED-IN WORD LENGTHS\n');
fprintf('=================================================\n');
fprintf('  %-22s  %4s  %4s  Format\n', 'Signal', 'WL', 'FL');
fprintf('  %-22s  %4s  %4s  ------\n', '------', '--', '--');
fprintf('  %-22s  %4d  %4d  Q%d.%d\n', 'Input samples', ...
        WL_x, FL_x, WL_x-FL_x-1, FL_x);
fprintf('  %-22s  %4d  %4d  Q%d.%d\n', 'Weights', ...
        WL_w, FL_w, WL_w-FL_w-1, FL_w);
fprintf('  %-22s  %4d  %4d  Q%d.%d\n', 'Multiplier output', ...
        WL_prod, FL_prod, WL_prod-FL_prod-1, FL_prod);
fprintf('  %-22s  %4d  %4d  Q%d.%d\n', 'Accumulator', ...
        WL_acc, FL_acc, WL_acc-FL_acc-1, FL_acc);
fprintf('  %-22s  %4d  %4d  Q%d.%d\n', 'Beamformer output', ...
        WL_out, FL_out, WL_out-FL_out-1, FL_out);
fprintf('  -------------------------------------------------\n');
fprintf('  Input scale factor    : %.6f\n', X_scale);
fprintf('  Max pattern deviation : %.4f dB  (< 0.5 dB target)\n', peak_dev_dB);
fprintf('  Null depth deviation  : %.4f dB  (< 5.0 dB target)\n', null_dev_dB);
fprintf('  3 dB BW deviation     : %.4f deg\n', abs(bw3_fixed - bw3_float));
fprintf('  Output SQNR           : %.2f dB\n', SQNR_dB);
fprintf('  SINR degradation      : %.2f dB\n', SINR_out_dB - SINR_fp_dB);
fprintf('=================================================\n');

% =========================================================================
% LOCAL FUNCTIONS
% =========================================================================

function q = quantize_fp(x, WL, FL)
% quantize_fp  Quantize double to signed fixed-point, nearest rounding + saturation.
%   Real and imaginary parts clipped independently — MATLAB min/max compare
%   complex numbers by magnitude, so we must never call them on complex arrays.
scale   = 2^FL;
max_val =  (2^(WL-1) - 1) / scale;
min_val = -(2^(WL-1))     / scale;
qr = round(real(x) * scale) / scale;
qi = round(imag(x) * scale) / scale;
qr(qr > max_val) = max_val;  qr(qr < min_val) = min_val;
qi(qi > max_val) = max_val;  qi(qi < min_val) = min_val;
if isreal(x),  q = qr;  else,  q = qr + 1j * qi;  end
end

function q = quantize_trunc(x, WL, FL)
% quantize_trunc  Floor (truncate toward -inf) rounding, wrap on overflow.
%                 Models Verilog default arithmetic truncation.
scale    = 2^FL;
mod_val  = 2^WL;
int_vals = floor(x * scale);
int_vals = mod(int_vals, mod_val);
int_vals(int_vals >= 2^(WL-1)) = int_vals(int_vals >= 2^(WL-1)) - mod_val;
q = int_vals / scale;
end

function q = quantize_sat(x, WL, FL)
% quantize_sat  Floor rounding with saturation — used at output stage.
scale   = 2^FL;
max_val =  (2^(WL-1) - 1) / scale;
min_val = -(2^(WL-1))     / scale;
q = floor(x * scale) / scale;
q = min(max(q, min_val), max_val);
end

function y_dbl = fpBeamformer(w_qd, X_qd, WL_out, FL_out)
% fpBeamformer  y(n) = w_q^H * x_q(n), full-precision accumulation, output quantized.
%   Phase 1.2 goal is to validate Q1.15 for inputs and weights — intermediate
%   pipeline precision is validated against this reference in Phase 1.4 RTL sim.
[~, N] = size(X_qd);
y_dbl  = zeros(1, N);
for n = 1:N
    acc   = w_qd' * X_qd(:, n);
    y_dbl(n) = quantize_sat(real(acc), WL_out, FL_out) + ...
           1j * quantize_sat(imag(acc), WL_out, FL_out);
end
end

function hex_str = to_hex2c(val, WL, FL)
% to_hex2c  Signed fixed-point double -> WL-bit two's-complement hex string.
int_val = round(val * 2^FL);
int_val = max(int_val, -2^(WL-1));
int_val = min(int_val,  2^(WL-1) - 1);
if int_val < 0,  int_val = int_val + 2^WL;  end
hex_str = dec2hex(int_val, WL/4);
end

function bw = beamwidth3dB(phi_deg, AF_dB)
% beamwidth3dB  3 dB beamwidth of a normalised dB radiation pattern.
[~, pk] = max(AF_dB);
above   = AF_dB >= -3;
trans   = diff(above);
rises   = find(trans ==  1);
falls   = find(trans == -1);
left    = rises(rises  < pk);
right   = falls(falls  > pk);
if isempty(left) || isempty(right),  bw = NaN;  return;  end
bw = phi_deg(right(1)) - phi_deg(left(end));
end

function a = steeringVector(theta_deg, M, d_over_lam)
psi = 2 * pi * d_over_lam * sind(theta_deg);
m   = (0:M-1)';
a   = exp(1j * m * psi);
end
diary off;