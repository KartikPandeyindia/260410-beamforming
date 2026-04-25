% =========================================================================
% Phase 2.2 — RLS Adaptive Beamformer Simulation
%
% Implements pilot-driven RLS weight update on the same signal environment
% as Phase 1.1 and Phase 2.1 (same seed, same array, same SNR/SIR).
% Compares convergence behaviour across forgetting factors and benchmarks
% against the Phase 1 fixed weight baseline and Phase 2.1 LMS result.
%
% Sections:
%   1. Parameters and signal generation  (identical to algo_sim.m / lms_sim.m)
%   2. Phase 1 fixed-weight baseline
%   3. RLS forgetting factor sweep
%   4. Best lambda — detailed analysis
%   5. Plots
%   6. Summary
% =========================================================================

clc; clear; close all;

cd(fileparts(mfilename('fullpath')));

if exist('command_line_output.txt','file'), delete('command_line_output.txt'); end
diary('command_line_output.txt');
diary on;

fprintf('=======================================================\n');
fprintf('  PHASE 2.2 — RLS ADAPTIVE BEAMFORMER SIMULATION\n');
fprintf('=======================================================\n\n');

% -------------------------------------------------------------------------
% 1. PARAMETERS AND SIGNAL GENERATION
%    Identical to algo_sim.m and lms_sim.m — same seed, same RNG draw order.
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
w_fixed       = a_sig / norm(a_sig);
sinr_fixed    = compute_sinr(w_fixed, a_sig, a_int, sig_power, int_power, noise_sigma);
sinr_fixed_dB = 10*log10(sinr_fixed);

% LMS best result (from Phase 2.1) for comparison
sinr_lms_dB = 18.93;

fprintf('Phase 1 fixed-weight SINR : %.2f dB\n', sinr_fixed_dB);
fprintf('Phase 2.1 LMS SINR        : %.2f dB\n\n', sinr_lms_dB);

% -------------------------------------------------------------------------
% 3. RLS FORGETTING FACTOR SWEEP
%    delta: initialisation parameter for P = delta^-1 * I
%    Small delta (aggressive init) speeds up early convergence.
% -------------------------------------------------------------------------
lambda_vals = [0.9, 0.95, 0.99, 0.999, 1.0];
delta       = 0.01;   % inverse of initial P diagonal
n_lam       = length(lambda_vals);
colors      = lines(n_lam);

mse_all    = zeros(n_lam, N_samples);
sinr_all   = zeros(n_lam, N_samples);
w_conv_all = zeros(M, n_lam);

for k = 1:n_lam
    lambda = lambda_vals(k);
    w = zeros(M, 1);
    P = (1/delta) * eye(M);

    for n = 1:N_samples
        x_n  = X(:, n);
        % Kalman gain
        Px   = P * x_n;
        denom = lambda + x_n' * Px;
        kk   = Px / denom;
        % Error and weight update
        e_n  = d(n) - w' * x_n;
        w    = w + kk * conj(e_n);
        % Covariance update
        P    = (P - kk * x_n' * P) / lambda;

        mse_all(k, n)  = abs(e_n)^2;
        sinr_all(k, n) = compute_sinr(w, a_sig, a_int, ...
                                      sig_power, int_power, noise_sigma);
    end
    w_conv_all(:, k) = w;
end

sinr_all_dB = 10*log10(max(sinr_all, 1e-10));

% -------------------------------------------------------------------------
% 4. BEST LAMBDA — pick lambda with highest converged SINR (last 50 samples)
% -------------------------------------------------------------------------
sinr_tail     = mean(sinr_all(:, end-49:end), 2);
[~, best_idx] = max(sinr_tail);
lambda_best   = lambda_vals(best_idx);
w_best        = w_conv_all(:, best_idx);

fprintf('Best forgetting factor : lambda = %.3f\n', lambda_best);

% Detailed run for best lambda — capture weight history
w        = zeros(M, 1);
P        = (1/delta) * eye(M);
w_hist   = zeros(M, N_samples);
mse_best = zeros(1, N_samples);
sinr_best = zeros(1, N_samples);

for n = 1:N_samples
    x_n  = X(:, n);
    Px   = P * x_n;
    denom = lambda_best + x_n' * Px;
    kk   = Px / denom;
    e_n  = d(n) - w' * x_n;
    w    = w + kk * conj(e_n);
    P    = (P - kk * x_n' * P) / lambda_best;

    w_hist(:, n)   = w;
    mse_best(n)    = abs(e_n)^2;
    sinr_best(n)   = compute_sinr(w, a_sig, a_int, ...
                                  sig_power, int_power, noise_sigma);
end
sinr_best_dB = 10*log10(max(sinr_best, 1e-10));
w_converged  = w;
sinr_rls_dB  = 10*log10(compute_sinr(w_converged, a_sig, a_int, ...
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

% ── Plot 1: Learning curves ───────────────────────────────────────────────
figure('Name','RLS Learning Curves','Position',[100 100 800 450]);
for k = 1:n_lam
    semilogy(1:N_samples, mse_all(k,:), 'Color', colors(k,:), ...
             'LineWidth', 1.2, 'DisplayName', sprintf('\\lambda = %.3f', lambda_vals(k)));
    hold on;
end
set(gca, 'YScale', 'log');
yline(noise_sigma^2, 'k--', 'LineWidth', 1.2, 'DisplayName', 'Noise floor');
ylim([1e-4 1e2]);
xlabel('Iteration (sample index)');
ylabel('Instantaneous |e(n)|^2');
title('RLS Learning Curves — Forgetting Factor Sweep');
legend('Location','northeast'); grid on;
saveas(gcf, fullfile(plot_dir, 'P2.2_RLS_Learning_Curves.png'));

% ── Plot 2: SINR vs iteration ─────────────────────────────────────────────
figure('Name','RLS SINR vs Iteration','Position',[100 100 800 450]);
for k = 1:n_lam
    plot(1:N_samples, sinr_all_dB(k,:), 'Color', colors(k,:), ...
         'LineWidth', 1.2, 'DisplayName', sprintf('\\lambda = %.3f', lambda_vals(k)));
    hold on;
end
yline(sinr_fixed_dB, 'k--', 'LineWidth', 1.5, 'DisplayName', 'Phase 1 fixed');
yline(sinr_lms_dB,   'b:',  'LineWidth', 1.5, 'DisplayName', 'LMS best');
xlabel('Iteration'); ylabel('SINR (dB)');
title('RLS SINR vs Iteration — Forgetting Factor Sweep');
legend('Location','southeast'); grid on;
saveas(gcf, fullfile(plot_dir, 'P2.2_RLS_SINR_Convergence.png'));

% ── Plot 3: Weight convergence trajectories (best lambda) ─────────────────
figure('Name','RLS Weight Convergence','Position',[100 100 900 550]);
subplot(2,1,1);
plot(1:N_samples, real(w_hist).', 'LineWidth', 1.0);
xlabel('Iteration'); ylabel('Re\{w_m\}');
title(sprintf('RLS Weight Convergence (\\lambda = %.3f) — Real Parts', lambda_best));
legend(arrayfun(@(k) sprintf('w_{%d}',k), 0:M-1, 'UniformOutput',false), ...
       'Location','eastoutside','FontSize',7); grid on;

subplot(2,1,2);
plot(1:N_samples, imag(w_hist).', 'LineWidth', 1.0);
xlabel('Iteration'); ylabel('Im\{w_m\}');
title('RLS Weight Convergence — Imaginary Parts');
legend(arrayfun(@(k) sprintf('w_{%d}',k), 0:M-1, 'UniformOutput',false), ...
       'Location','eastoutside','FontSize',7); grid on;
saveas(gcf, fullfile(plot_dir, 'P2.2_RLS_Weight_Convergence.png'));

% ── Plot 4: Radiation pattern — RLS vs LMS vs Phase 1 ────────────────────
phi_deg  = linspace(-90, 90, 1801);
AF_fixed = zeros(1, length(phi_deg));
AF_rls   = zeros(1, length(phi_deg));

% Recompute LMS converged weights for comparison (same signal, mu=0.001)
w_lms = zeros(M,1);
for n = 1:N_samples
    x_n  = X(:,n);
    e_n  = d(n) - w_lms' * x_n;
    w_lms = w_lms + 0.001 * conj(e_n) * x_n;
end
AF_lms = zeros(1, length(phi_deg));

for t = 1:length(phi_deg)
    a_t      = steeringVector(phi_deg(t), M, d_over_lam);
    AF_fixed(t) = abs(w_fixed'     * a_t);
    AF_rls(t)   = abs(w_converged' * a_t);
    AF_lms(t)   = abs(w_lms'       * a_t);
end

to_dB = @(af) 20*log10(af / max(af) + 1e-12);

figure('Name','Radiation Pattern Comparison','Position',[100 100 800 500]);
plot(phi_deg, to_dB(AF_fixed), 'b-',  'LineWidth', 1.8, 'DisplayName','Phase 1 Fixed'); hold on;
plot(phi_deg, to_dB(AF_rls),   'r--', 'LineWidth', 1.8, 'DisplayName','RLS Converged');
plot(phi_deg, to_dB(AF_lms),   'g:',  'LineWidth', 1.5, 'DisplayName','LMS Converged');
xline(theta_sig, 'k:', 'LineWidth', 1, 'Label', sprintf('%d°', theta_sig), 'HandleVisibility','off');
xline(theta_int, 'm:', 'LineWidth', 1, 'Label', sprintf('%d°', theta_int), 'HandleVisibility','off');
ylim([-60 5]); xlim([-90 90]);
xlabel('Angle (degrees)'); ylabel('Normalised AF (dB)');
title(sprintf('Radiation Pattern: Phase 1 vs RLS vs LMS (\\lambda = %.3f)', lambda_best));
legend('Location','southwest'); grid on;
saveas(gcf, fullfile(plot_dir, 'P2.2_RLS_Pattern_Comparison.png'));

% ── Plot 5: LMS vs RLS SINR convergence head-to-head ─────────────────────
% Rerun LMS SINR history for fair comparison
sinr_lms_hist = zeros(1, N_samples);
w_lms2 = zeros(M,1);
for n = 1:N_samples
    x_n   = X(:,n);
    e_n   = d(n) - w_lms2' * x_n;
    w_lms2 = w_lms2 + 0.001 * conj(e_n) * x_n;
    sinr_lms_hist(n) = compute_sinr(w_lms2, a_sig, a_int, ...
                                     sig_power, int_power, noise_sigma);
end

figure('Name','LMS vs RLS Head-to-Head','Position',[100 100 800 450]);
plot(1:N_samples, 10*log10(max(sinr_lms_hist,1e-10)), 'b-', ...
     'LineWidth', 1.5, 'DisplayName', sprintf('LMS (\\mu=0.001)')); hold on;
plot(1:N_samples, sinr_best_dB, 'r-', ...
     'LineWidth', 1.5, 'DisplayName', sprintf('RLS (\\lambda=%.3f)', lambda_best));
yline(sinr_fixed_dB, 'k--', 'LineWidth', 1.5, 'DisplayName', 'Phase 1 fixed');
xlabel('Iteration'); ylabel('SINR (dB)');
title('LMS vs RLS — SINR Convergence Head-to-Head');
legend('Location','southeast'); grid on;
xlim([0 100]);   % zoom in on early convergence
saveas(gcf, fullfile(plot_dir, 'P2.2_LMS_vs_RLS_Headtohead.png'));

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
fprintf('  Phase 2.1 LMS SINR           : %+.2f dB\n', sinr_lms_dB);
fprintf('  RLS converged SINR           : %+.2f dB  (lambda=%.3f)\n', ...
        sinr_rls_dB, lambda_best);
fprintf('  RLS delta vs fixed           : %+.2f dB\n', sinr_rls_dB - sinr_fixed_dB);
fprintf('  RLS delta vs LMS             : %+.2f dB\n', sinr_rls_dB - sinr_lms_dB);
fprintf('  Convergence sample (<1dB gap): %d / %d\n', conv_sample, N_samples);
fprintf('-------------------------------------------------------\n');
fprintf('  Forgetting factor sweep results:\n');
for k = 1:n_lam
    sinr_k = 10*log10(compute_sinr(w_conv_all(:,k), a_sig, a_int, ...
                                    sig_power, int_power, noise_sigma));
    fprintf('    lambda = %.3f  ->  converged SINR = %.2f dB\n', lambda_vals(k), sinr_k);
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
