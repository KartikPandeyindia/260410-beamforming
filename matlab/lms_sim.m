% =========================================================================
% Phase 2.1 — LMS Adaptive Beamformer Simulation
%
% Implements pilot-driven LMS weight update on the same signal environment
% as Phase 1.1 (same seed, same array, same SNR/SIR). Compares convergence
% behaviour across step sizes and benchmarks against the Phase 1 fixed
% weight baseline.
%
% Sections:
%   1. Parameters and signal generation  (identical to algo_sim.m)
%   2. Phase 1 fixed-weight baseline
%   3. LMS step-size sweep
%   4. Best step size — detailed analysis
%   5. Plots
%   6. Summary
% =========================================================================

clc; clear; close all;

cd(fileparts(mfilename('fullpath')));

if exist('command_line_output.txt','file'), delete('command_line_output.txt'); end
diary('command_line_output.txt');
diary on;

fprintf('=======================================================\n');
fprintf('  PHASE 2.1 — LMS ADAPTIVE BEAMFORMER SIMULATION\n');
fprintf('=======================================================\n\n');

% -------------------------------------------------------------------------
% 1. PARAMETERS AND SIGNAL GENERATION
%    Identical to algo_sim.m — same seed, same order of RNG draws.
% -------------------------------------------------------------------------
M          = 8;
d_over_lam = 0.5;
theta_sig  = 30;
theta_int  = -20;
SNR_dB     = 10;
SIR_dB     = 0;
N_samples  = 512;

rng(42);

SNR_lin     = 10^(SNR_dB / 10);
SIR_lin     = 10^(SIR_dB / 10);
sig_power   = 1.0;
noise_sigma = sqrt(sig_power / SNR_lin);
int_power   = sig_power / SIR_lin;

a_sig = steeringVector(theta_sig, M, d_over_lam);
a_int = steeringVector(theta_int, M, d_over_lam);

s     = (randn(1, N_samples) + 1j * randn(1, N_samples)) / sqrt(2);
i_sig = (randn(1, N_samples) + 1j * randn(1, N_samples)) / sqrt(2);
noise = noise_sigma * (randn(M, N_samples) + 1j * randn(M, N_samples)) / sqrt(2);

X = a_sig * s + sqrt(int_power) * a_int * i_sig + noise;
d = s;   % pilot (desired signal)

% -------------------------------------------------------------------------
% 2. PHASE 1 FIXED-WEIGHT BASELINE
% -------------------------------------------------------------------------
w_fixed      = a_sig / norm(a_sig);
sinr_fixed   = compute_sinr(w_fixed, a_sig, a_int, sig_power, int_power, noise_sigma);
sinr_fixed_dB = 10*log10(sinr_fixed);

fprintf('Phase 1 fixed-weight SINR : %.2f dB\n\n', sinr_fixed_dB);

% -------------------------------------------------------------------------
% 3. LMS STEP-SIZE SWEEP
% -------------------------------------------------------------------------
mu_vals   = [0.001, 0.005, 0.01, 0.05, 0.1];
n_mu      = length(mu_vals);
colors    = lines(n_mu);

mse_all    = zeros(n_mu, N_samples);
sinr_all   = zeros(n_mu, N_samples);
w_conv_all = zeros(M, n_mu);

for k = 1:n_mu
    mu = mu_vals(k);
    w  = zeros(M, 1);

    for n = 1:N_samples
        x_n = X(:, n);
        y_n = w' * x_n;
        e_n = d(n) - y_n;
        w   = w + mu * conj(e_n) * x_n;

        mse_all(k, n)  = abs(e_n)^2;
        sinr_all(k, n) = compute_sinr(w, a_sig, a_int, ...
                                      sig_power, int_power, noise_sigma);
    end
    w_conv_all(:, k) = w;
end

sinr_all_dB = 10*log10(max(sinr_all, 1e-10));

% -------------------------------------------------------------------------
% 4. BEST STEP SIZE — pick mu with highest converged SINR (last 50 samples)
% -------------------------------------------------------------------------
sinr_tail     = mean(sinr_all(:, end-49:end), 2);
[~, best_idx] = max(sinr_tail);
mu_best       = mu_vals(best_idx);
w_best        = w_conv_all(:, best_idx);

fprintf('Best step size : mu = %.3f\n', mu_best);

% Detailed convergence run for best mu — capture weight history
w        = zeros(M, 1);
w_hist   = zeros(M, N_samples);
mse_best = zeros(1, N_samples);
sinr_best = zeros(1, N_samples);

for n = 1:N_samples
    x_n = X(:, n);
    y_n = w' * x_n;
    e_n = d(n) - y_n;
    w   = w + mu_best * conj(e_n) * x_n;

    w_hist(:, n)   = w;
    mse_best(n)    = abs(e_n)^2;
    sinr_best(n)   = compute_sinr(w, a_sig, a_int, ...
                                  sig_power, int_power, noise_sigma);
end
sinr_best_dB = 10*log10(max(sinr_best, 1e-10));
w_converged  = w;
sinr_lms_dB  = 10*log10(compute_sinr(w_converged, a_sig, a_int, ...
                                      sig_power, int_power, noise_sigma));

% Convergence sample: first n where SINR within 1 dB of fixed baseline
conv_sample = N_samples;
for n = 1:N_samples
    if sinr_best_dB(n) >= sinr_fixed_dB - 1
        conv_sample = n;
        break;
    end
end

% -------------------------------------------------------------------------
% 5. PLOTS
% -------------------------------------------------------------------------
plot_dir = '../plots';

% ── Plot 1: Learning curves (MSE vs iteration) ───────────────────────────
figure('Name','LMS Learning Curves','Position',[100 100 800 450]);
for k = 1:n_mu
    semilogy(1:N_samples, mse_all(k,:), 'Color', colors(k,:), ...
             'LineWidth', 1.2, 'DisplayName', sprintf('\\mu = %.3f', mu_vals(k)));
    hold on;
end
set(gca, 'YScale', 'log');
yline(noise_sigma^2, 'k--', 'LineWidth', 1.2, 'DisplayName', 'Noise floor');
ylim([1e-4 1e6]);
xlabel('Iteration (sample index)');
ylabel('Instantaneous |e(n)|^2');
title('LMS Learning Curves — Step Size Sweep');
legend('Location','northeast'); grid on;
saveas(gcf, fullfile(plot_dir, 'P2.1_LMS_Learning_Curves.png'));

% ── Plot 2: SINR vs iteration ─────────────────────────────────────────────
figure('Name','LMS SINR vs Iteration','Position',[100 100 800 450]);
hold on;
for k = 1:n_mu
    plot(1:N_samples, sinr_all_dB(k,:), 'Color', colors(k,:), ...
         'LineWidth', 1.2, 'DisplayName', sprintf('\\mu = %.3f', mu_vals(k)));
end
yline(sinr_fixed_dB, 'k--', 'LineWidth', 1.5, 'DisplayName', 'Phase 1 fixed');
xlabel('Iteration'); ylabel('SINR (dB)');
title('LMS SINR vs Iteration — Step Size Sweep');
legend('Location','southeast'); grid on;
saveas(gcf, fullfile(plot_dir, 'P2.1_LMS_SINR_Convergence.png'));

% ── Plot 3: Weight convergence trajectories (best mu) ────────────────────
figure('Name','LMS Weight Convergence','Position',[100 100 900 550]);
subplot(2,1,1);
plot(1:N_samples, real(w_hist).', 'LineWidth', 1.0);
xlabel('Iteration'); ylabel('Re\{w_m\}');
title(sprintf('LMS Weight Convergence (\\mu = %.3f) — Real Parts', mu_best));
legend(arrayfun(@(k) sprintf('w_{%d}',k), 0:M-1, 'UniformOutput',false), ...
       'Location','eastoutside','FontSize',7); grid on;

subplot(2,1,2);
plot(1:N_samples, imag(w_hist).', 'LineWidth', 1.0);
xlabel('Iteration'); ylabel('Im\{w_m\}');
title('LMS Weight Convergence — Imaginary Parts');
legend(arrayfun(@(k) sprintf('w_{%d}',k), 0:M-1, 'UniformOutput',false), ...
       'Location','eastoutside','FontSize',7); grid on;
saveas(gcf, fullfile(plot_dir, 'P2.1_LMS_Weight_Convergence.png'));

% ── Plot 4: Radiation pattern — initial vs LMS vs Phase 1 ────────────────
phi_deg = linspace(-90, 90, 1801);
w_init  = ones(M,1) / sqrt(M);
AF_fixed = zeros(1, length(phi_deg));
AF_lms   = zeros(1, length(phi_deg));
AF_init  = zeros(1, length(phi_deg));

for t = 1:length(phi_deg)
    a_t      = steeringVector(phi_deg(t), M, d_over_lam);
    AF_fixed(t) = abs(w_fixed'    * a_t);
    AF_lms(t)   = abs(w_converged' * a_t);
    AF_init(t)  = abs(w_init'     * a_t);
end

to_dB = @(af) 20*log10(af / max(af) + 1e-12);
AF_fixed_dB = to_dB(AF_fixed);
AF_lms_dB   = to_dB(AF_lms);
AF_init_dB  = to_dB(AF_init);

figure('Name','Radiation Pattern Comparison','Position',[100 100 800 500]);
plot(phi_deg, AF_fixed_dB, 'b-',  'LineWidth', 1.8, 'DisplayName','Phase 1 Fixed'); hold on;
plot(phi_deg, AF_lms_dB,   'r--', 'LineWidth', 1.8, 'DisplayName','LMS Converged');
plot(phi_deg, AF_init_dB,  'g:',  'LineWidth', 1.2, 'DisplayName','LMS Initial (uniform)');
xline(theta_sig,  'k:', 'LineWidth', 1, 'Label', sprintf('%d°', theta_sig), 'HandleVisibility','off');
xline(theta_int,  'm:', 'LineWidth', 1, 'Label', sprintf('%d°', theta_int), 'HandleVisibility','off');
ylim([-60 5]); xlim([-90 90]);
xlabel('Angle (degrees)'); ylabel('Normalised AF (dB)');
title(sprintf('Radiation Pattern: Phase 1 vs LMS Converged (\\mu = %.3f)', mu_best));
legend('Location','southwest'); grid on;
saveas(gcf, fullfile(plot_dir, 'P2.1_LMS_Pattern_Comparison.png'));

% ── Plot 5: Beamformed output — LMS converged weights ────────────────────
y_lms   = w_converged' * X;
y_fixed = w_fixed' * X;
n_plot  = 80;

figure('Name','LMS Output vs Desired','Position',[100 100 800 500]);
subplot(2,1,1);
plot(0:n_plot-1, real(y_lms(1:n_plot)),   'r-',  'LineWidth',1.0); hold on;
plot(0:n_plot-1, real(y_fixed(1:n_plot)), 'b--', 'LineWidth',1.0);
plot(0:n_plot-1, real(s(1:n_plot)),       'g:',  'LineWidth',0.8);
xlabel('Sample'); ylabel('Amplitude');
title('Beamformer output — real part');
legend('LMS converged','Phase 1 fixed','Desired s(n)'); grid on;

subplot(2,1,2);
plot(0:n_plot-1, imag(y_lms(1:n_plot)),   'r-',  'LineWidth',1.0); hold on;
plot(0:n_plot-1, imag(y_fixed(1:n_plot)), 'b--', 'LineWidth',1.0);
plot(0:n_plot-1, imag(s(1:n_plot)),       'g:',  'LineWidth',0.8);
xlabel('Sample'); ylabel('Amplitude');
title('Beamformer output — imaginary part');
legend('LMS converged','Phase 1 fixed','Desired s(n)'); grid on;
saveas(gcf, fullfile(plot_dir, 'P2.1_LMS_Output_Comparison.png'));

% -------------------------------------------------------------------------
% 6. SUMMARY
% -------------------------------------------------------------------------
fprintf('\n=======================================================\n');
fprintf('  RESULTS SUMMARY\n');
fprintf('=======================================================\n');
fprintf('  Array: M=%d, d/lam=%.1f\n', M, d_over_lam);
fprintf('  Target: %.0f deg  |  Interferer: %.0f deg\n', theta_sig, theta_int);
fprintf('  SNR: %.0f dB  |  SIR: %.0f dB\n', SNR_dB, SIR_dB);
fprintf('-------------------------------------------------------\n');
fprintf('  Phase 1 fixed-weight SINR    : %+.2f dB\n', sinr_fixed_dB);
fprintf('  LMS converged SINR           : %+.2f dB  (mu=%.3f)\n', ...
        sinr_lms_dB, mu_best);
fprintf('  SINR delta (LMS - fixed)     : %+.2f dB\n', sinr_lms_dB - sinr_fixed_dB);
fprintf('  Convergence sample (<1dB gap): %d / %d\n', conv_sample, N_samples);
fprintf('-------------------------------------------------------\n');
fprintf('  Step size sweep results:\n');
for k = 1:n_mu
    sinr_k = 10*log10(compute_sinr(w_conv_all(:,k), a_sig, a_int, ...
                                    sig_power, int_power, noise_sigma));
    fprintf('    mu = %.3f  ->  converged SINR = %.2f dB\n', mu_vals(k), sinr_k);
end
fprintf('=======================================================\n');

diary off;

% =========================================================================
% LOCAL FUNCTIONS
% =========================================================================
function a = steeringVector(theta_deg, M, d_over_lam)
    psi = 2 * pi * d_over_lam * sind(theta_deg);
    m   = (0:M-1)';
    a   = exp(1j * m * psi);
end

function sinr = compute_sinr(w, a_sig, a_int, sig_power, int_power, noise_sigma)
    if norm(w) < 1e-12
        sinr = 1e-10;
        return;
    end
    p_sig   = sig_power  * abs(w' * a_sig)^2;
    p_int   = int_power  * abs(w' * a_int)^2;
    p_noise = noise_sigma^2 * real(w' * w);
    sinr    = real(p_sig) / real(p_int + p_noise);
end
