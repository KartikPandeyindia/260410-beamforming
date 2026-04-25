function env = signal_setup()
% signal_setup  Canonical signal environment for all beamformer simulations.
%
% Returns a struct containing all parameters and generated signals used
% consistently across Phase 1.1, 1.2, 2.1, 2.2, and 2.3. Calling this
% function guarantees identical array geometry, channel conditions, and
% RNG draw order across scripts.
%
% Usage:
%   env = signal_setup();
%
% Output struct fields:
%   Array geometry
%     .M           - number of antenna elements (8)
%     .d_over_lam  - element spacing / wavelength (0.5)
%   Source geometry
%     .theta_sig   - target signal angle, degrees (30)
%     .theta_int   - interferer angle, degrees (-20)
%   Channel parameters
%     .SNR_dB      - input SNR in dB (10)
%     .SIR_dB      - input SIR in dB (0)
%     .N_samples   - number of time-domain samples (512)
%   Derived power quantities
%     .sig_power   - desired signal power (1.0)
%     .noise_sigma - noise standard deviation per element
%     .int_power   - interferer power
%   Steering vectors (M x 1 complex)
%     .a_sig       - steering vector toward target
%     .a_int       - steering vector toward interferer
%   Generated signals
%     .X           - received array signal matrix (M x N_samples)
%     .d           - pilot / desired signal (1 x N_samples)
%     .s           - clean desired signal, same as d (1 x N_samples)
%
% IMPORTANT: rng(42) is called inside this function. Any script that calls
% signal_setup() must NOT call rng() before or after, as that would alter
% the RNG state and break cross-script reproducibility.

    % -----------------------------------------------------------------
    % Array and channel parameters
    % -----------------------------------------------------------------
    env.M          = 8;
    env.d_over_lam = 0.5;
    env.theta_sig  = 30;
    env.theta_int  = -20;
    env.SNR_dB     = 10;
    env.SIR_dB     = 0;
    env.N_samples  = 512;

    % -----------------------------------------------------------------
    % Derived power quantities
    % -----------------------------------------------------------------
    SNR_lin        = 10^(env.SNR_dB / 10);
    SIR_lin        = 10^(env.SIR_dB / 10);
    env.sig_power  = 1.0;
    env.noise_sigma = sqrt(env.sig_power / SNR_lin);
    env.int_power  = env.sig_power / SIR_lin;

    % -----------------------------------------------------------------
    % Steering vectors
    % -----------------------------------------------------------------
    env.a_sig = steeringVector(env.theta_sig, env.M, env.d_over_lam);
    env.a_int = steeringVector(env.theta_int, env.M, env.d_over_lam);

    % -----------------------------------------------------------------
    % Signal generation — rng(42) ensures reproducibility
    % Draw order matches algo_sim.m, lms_sim.m, rls_sim.m exactly:
    %   1. s      (1 x N_samples complex)
    %   2. i_sig  (1 x N_samples complex)
    %   3. noise  (M x N_samples complex)
    % -----------------------------------------------------------------
    rng(42);

    M   = env.M;
    N   = env.N_samples;

    s     = (randn(1, N) + 1j * randn(1, N)) / sqrt(2);
    i_sig = (randn(1, N) + 1j * randn(1, N)) / sqrt(2);
    noise = env.noise_sigma * (randn(M, N) + 1j * randn(M, N)) / sqrt(2);

    env.X = env.a_sig * s + sqrt(env.int_power) * env.a_int * i_sig + noise;
    env.s = s;
    env.d = s;   % pilot equals desired signal (perfect pilot assumption)
end

% -------------------------------------------------------------------------
% Local helper
% -------------------------------------------------------------------------
function a = steeringVector(theta_deg, M, d_over_lam)
    psi = 2 * pi * d_over_lam * sind(theta_deg);
    m   = (0:M-1)';
    a   = exp(1j * m * psi);
end
