% =========================================================================
% Phase 1.1 — Fixed Beamformer Simulation (Floating-Point)
% Uniform Linear Array (ULA), Delay-and-Sum Beamforming
% Golden reference for FPGA implementation
%
% Sections:
%   1. Parameters
%   2. Steering vector
%   3. Signal generation
%   4. Beamforming weights
%   5. Apply beamformer
%   6. Radiation pattern
%   7. Metrics (SINR)
%   8. Plots
% =========================================================================

clc; clear; close all;

% -------------------------------------------------------------------------
% 1. SIGNAL ENVIRONMENT
%    All parameters and generated signals from the canonical signal model.
%    See signal_setup.m for array geometry, channel conditions, and RNG.
% -------------------------------------------------------------------------
env         = signal_setup();
M           = env.M;
d_over_lam  = env.d_over_lam;
theta_sig   = env.theta_sig;
theta_int   = env.theta_int;
SNR_dB      = env.SNR_dB;
SIR_dB      = env.SIR_dB;
N_samples   = env.N_samples;
sig_power   = env.sig_power;
noise_sigma = env.noise_sigma;
int_power   = env.int_power;
a_sig       = env.a_sig;
a_int       = env.a_int;
X           = env.X;
s           = env.s;

% -------------------------------------------------------------------------
% 4. BEAMFORMING WEIGHTS
%
%    Conventional (delay-and-sum) beamformer:
%       w = a(theta_sig)
%
%    This sets the weight of each antenna to the conjugate of the expected
%    phase, so all contributions from theta_sig add in phase (coherently).
%
%    Normalise so ||w||^2 = 1 (unit norm → fair gain comparison)
% -------------------------------------------------------------------------
w = a_sig;
w = w / norm(w);       % Normalise  (M x 1)

% -------------------------------------------------------------------------
% 5. APPLY BEAMFORMER
%
%    Output: y(n) = w^H * x(n)
%
%    w^H is the conjugate transpose of w.
%    y(n) is a scalar for each time sample — the beamformed signal.
% -------------------------------------------------------------------------
y = w' * X;            % (1 x N_samples)

% -------------------------------------------------------------------------
% 6. RADIATION PATTERN (Array Factor)
%
%    Sweep a look angle phi from -90° to +90°.
%    For each phi, compute the array gain:
%       AF(phi) = |w^H * a(phi)|
%
%    This is what the beamformer "sees" from each direction.
%    Normalise to 0 dB at peak, then convert to dB.
% -------------------------------------------------------------------------
phi_deg = linspace(-90, 90, 1801);
AF      = zeros(1, length(phi_deg));

for k = 1:length(phi_deg)
    a_phi  = steeringVector(phi_deg(k), M, d_over_lam);
    AF(k)  = abs(w' * a_phi);
end

AF_norm = AF / max(AF);             % Normalise to peak = 1
AF_dB   = 20 * log10(AF_norm + 1e-12);  % Convert to dB

% -------------------------------------------------------------------------
% 7. METRICS — SINR
%
%    Gain toward signal and interferer directions
%    Input SINR:  before beamforming, across M antennas
%    Output SINR: after beamforming
% -------------------------------------------------------------------------
gain_sig = abs(w' * a_sig)^2;
gain_int = abs(w' * a_int)^2;

P_out_sig = gain_sig * sig_power;
P_out_int = gain_int * int_power;
P_out_n   = noise_sigma^2 * norm(w)^2;

SINR_in_dB  = 10*log10(sig_power / (int_power + noise_sigma^2 * M));
SINR_out_dB = 10*log10(P_out_sig / (P_out_int + P_out_n));

fprintf('=================================================\n');
fprintf('  BEAMFORMER SIMULATION RESULTS\n');
fprintf('=================================================\n');
fprintf('  Array         : M = %d elements, d/lambda = %.1f\n', M, d_over_lam);
fprintf('  Target angle  : %.1f deg\n', theta_sig);
fprintf('  Interferer    : %.1f deg\n', theta_int);
fprintf('  Input SNR     : %.1f dB\n', SNR_dB);
fprintf('  Input SIR     : %.1f dB\n', SIR_dB);
fprintf('--------------------------------------------------\n');
fprintf('  Array gain (signal)     : %+.2f dB\n', 10*log10(gain_sig));
fprintf('  Array gain (interferer) : %+.2f dB\n', 10*log10(gain_int));
fprintf('--------------------------------------------------\n');
fprintf('  Input  SINR   : %.2f dB\n', SINR_in_dB);
fprintf('  Output SINR   : %.2f dB\n', SINR_out_dB);
fprintf('  SINR improvement : %.2f dB\n', SINR_out_dB - SINR_in_dB);
fprintf('=================================================\n');

% -------------------------------------------------------------------------
% 8. PLOTS
% -------------------------------------------------------------------------

% --- Figure 1: Radiation Pattern (Rectangular) ---------------------------
figure('Name', 'Radiation Pattern', 'NumberTitle', 'off');
plot(phi_deg, AF_dB, 'b-', 'LineWidth', 1.5); hold on;
xline(theta_sig, 'g--', 'LineWidth', 1.2, ...
      'Label', sprintf('Target %.0f°', theta_sig), ...
      'LabelVerticalAlignment', 'bottom');
xline(theta_int, 'r--', 'LineWidth', 1.2, ...
      'Label', sprintf('Interferer %.0f°', theta_int), ...
      'LabelVerticalAlignment', 'bottom');
yline(-3,  'k:', 'LineWidth', 0.8, 'Label', '-3 dB');
yline(-10, 'k:', 'LineWidth', 0.8, 'Label', '-10 dB');
hold off;
xlim([-90 90]);  ylim([-60 5]);
xlabel('Angle (degrees)');
ylabel('Normalised array gain (dB)');
title(sprintf('Radiation pattern — M=%d, \\theta_{sig}=%.0f°, \\theta_{int}=%.0f°', ...
              M, theta_sig, theta_int));
grid on;  grid minor;
legend('Array factor', 'Target', 'Interferer', 'Location', 'southeast');

% --- Figure 2: Polar Radiation Pattern -----------------------------------
figure('Name', 'Polar Pattern', 'NumberTitle', 'off');
AF_polar = max(AF_dB, -40) + 40;      % Floor at -40 dB, shift up for polar
polarplot(deg2rad(phi_deg), AF_polar, 'b-', 'LineWidth', 1.5); hold on;
polarplot([deg2rad(theta_sig) deg2rad(theta_sig)], [0 40], 'g--', 'LineWidth', 1.2);
polarplot([deg2rad(theta_int) deg2rad(theta_int)], [0 40], 'r--', 'LineWidth', 1.2);
hold off;
ax = gca;
ax.ThetaZeroLocation = 'top';
ax.ThetaDir   = 'clockwise';
title('Polar radiation pattern');
legend('Array factor', 'Target', 'Interferer', 'Location', 'southoutside');

% --- Figure 3: Beamforming Weights ---------------------------------------
figure('Name', 'Beamforming Weights', 'NumberTitle', 'off');
m_idx = 0:M-1;

subplot(2,1,1);
bar(m_idx, [real(w), imag(w)]);
xlabel('Antenna index');
ylabel('Weight value');
title('Beamforming weights — real and imaginary parts');
legend('Re(w)', 'Im(w)');
grid on;

subplot(2,1,2);
phases = unwrap(angle(w)) * 180/pi;
plot(m_idx, phases, 'go-', 'LineWidth', 1.5, 'MarkerSize', 7); hold on;

% Overlay the expected linear phase slope
psi_expected = 360 * d_over_lam * sind(theta_sig);  % degrees per element
expected_phase = mod(m_idx * psi_expected + 180, 360) - 180;
plot(m_idx, expected_phase, 'b--', 'LineWidth', 1.0);
hold off;

xlabel('Antenna index');
ylabel('Phase (degrees)');
title(sprintf('Weight phases — expected \\Delta\\phi = %.1f°/element', psi_expected));
legend('Actual phase', 'Expected linear phase');
xticks(m_idx);
grid on;

% --- Figure 4: Beamformer Output (Time Domain) ---------------------------
figure('Name', 'Beamformer Output', 'NumberTitle', 'off');
n_plot = 80;    % Show first 80 samples
subplot(2,1,1);
plot(0:n_plot-1, real(y(1:n_plot)), 'b-', 'LineWidth', 1.0); hold on;
plot(0:n_plot-1, real(s(1:n_plot)), 'g--', 'LineWidth', 0.8);
hold off;
xlabel('Sample index');
ylabel('Amplitude');
title('Beamformer output vs desired signal — real part');
legend('Re(y) — BF output', 'Re(s) — desired signal');
grid on;

subplot(2,1,2);
plot(0:n_plot-1, imag(y(1:n_plot)), 'b-', 'LineWidth', 1.0); hold on;
plot(0:n_plot-1, imag(s(1:n_plot)), 'g--', 'LineWidth', 0.8);
hold off;
xlabel('Sample index');
ylabel('Amplitude');
title('Beamformer output vs desired signal — imaginary part');
legend('Im(y) — BF output', 'Im(s) — desired signal');
grid on;

% =========================================================================
% LOCAL FUNCTION — Steering Vector
% =========================================================================
function a = steeringVector(theta_deg, M, d_over_lam)
% steeringVector   Compute ULA steering vector
%
%   a = steeringVector(theta_deg, M, d_over_lam)
%
%   Inputs:
%     theta_deg   : angle of arrival in degrees (from broadside)
%     M           : number of antenna elements
%     d_over_lam  : element spacing normalised by wavelength
%
%   Output:
%     a           : M x 1 complex steering vector
%
%   Formula:
%     psi  = 2*pi * d_over_lam * sin(theta)
%     a(m) = exp(j * m * psi),   m = 0, 1, ..., M-1

    psi = 2 * pi * d_over_lam * sind(theta_deg);   % phase shift per element
    m   = (0:M-1)';                                 % element indices (M x 1)
    a   = exp(1j * m * psi);                        % steering vector (M x 1)
end