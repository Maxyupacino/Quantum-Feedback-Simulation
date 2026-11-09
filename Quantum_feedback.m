%% 第一部分：提取数据
clc; clear; close all;

%% 参数设置
Fs = 10e6;          % 采样率：10 MHz (10 * 10^6 samples/second)
dt = 1 / Fs;        % 采样间隔：0.1 微秒 (100 ns)

% 频谱仪模拟参数
% NFFT 决定了频率分辨率 (类似频谱仪的 RBW)。值越大，频率分辨率越高，但曲线越噪
nfft = 16384;       
window = hann(nfft); % 使用汉宁窗减小频谱泄漏
noverlap = floor(nfft / 2); % 50% 重叠，平滑数据 (类似频谱仪的 VBW 平均效果)

%% 1. 读取并处理【压缩光】数据
% 弹出对话框选择压缩光文件
disp('请在弹出的窗口中选择【压缩光】数据文件...');
[sqz_file, path] = uigetfile({'*.txt;*.csv;*.xlsx;*.dat', '数据文件 (*.txt, *.csv, *.xlsx, *.dat)'; '*.*', '所有文件 (*.*)'}, '请选择【压缩光】数据文件');

if isequal(sqz_file, 0)
    error('未选择压缩光文件，程序终止。');
end

% 拼接完整路径并读取数据
sqz_fullpath = fullfile(path, sqz_file);
fprintf('正在读取压缩光数据: %s\n', sqz_file);
sqz_data_raw = readmatrix(sqz_fullpath);

% 提取第二列 (signal) 和第三列 (idler)，并取绝对值
% 取绝对值以解决采集端一正一负的问题
sqz_signal = abs(sqz_data_raw(:, 2));
sqz_idler  = abs(sqz_data_raw(:, 3));

%% 2. 读取并处理【相干光】数据（散粒噪声极限 / SNL 基准）
% 弹出对话框选择相干光文件（默认打开刚才压缩光所在的同一个文件夹）
disp('请在弹出的窗口中选择【相干光】数据文件...');
[coh_file, ~] = uigetfile({'*.txt;*.csv;*.xlsx;*.dat', '数据文件 (*.txt, *.csv, *.xlsx, *.dat)'; '*.*', '所有文件 (*.*)'}, '请选择【相干光】数据文件', path);

if isequal(coh_file, 0)
    error('未选择相干光文件，程序终止。');
end

% 拼接完整路径并读取数据
coh_fullpath = fullfile(path, coh_file);
fprintf('正在读取相干光数据: %s\n', coh_file);
coh_data_raw = readmatrix(coh_fullpath);

% 同样提取第二列 (signal) 和第三列 (idler)，并取绝对值
coh_signal = abs(coh_data_raw(:, 2));
coh_idler  = abs(coh_data_raw(:, 3));

%% 数据提取完成提示
disp('--------------------------------------------------');
fprintf('数据提取并取绝对值完成！\n');
fprintf('压缩光数据长度: %d 组\n', length(sqz_signal));
fprintf('相干光数据长度: %d 组\n', length(coh_signal));
disp('--------------------------------------------------');

%% 第二部分：宽带差分噪声功率谱 (加入严格 AC 耦合修正)
run_part6 = 0;   

if run_part6
    disp('正在执行第六部分：计算严格 AC 耦合后的宽带差分功率谱...');

    % 1. 严格 AC 耦合 (彻底消除两路探测器的宏观光强不平衡与直流失配)
    sqz_sig_ac = sqz_signal - mean(sqz_signal);
    sqz_idl_ac = sqz_idler - mean(sqz_idler);
    coh_sig_ac = coh_signal - mean(coh_signal);
    coh_idl_ac = coh_idler - mean(coh_idler);

    % 2. 纯交流涨落作差
    % 此时的差分信号中已经没有任何直流残留，完全是量子与经典涨落的叠加
    diff_sqz_ac = sqz_sig_ac - sqz_idl_ac;
    diff_coh_ac = coh_sig_ac - coh_idl_ac;

    % 3. 宽带 PSD 参数设置 (为了看清 MHz 级别的宽谱，使用较大的 nfft)
    nfft_wide = 16384;       
    window_wide = hann(nfft_wide); 
    noverlap_wide = floor(nfft_wide / 2);

    % 4. 计算功率谱密度
    [pxx_sqz_w, f_w] = pwelch(diff_sqz_ac, window_wide, noverlap_wide, nfft_wide, Fs);
    [pxx_coh_w, ~]   = pwelch(diff_coh_ac, window_wide, noverlap_wide, nfft_wide, Fs);

    % 转换为 dB 尺度
    pxx_sqz_w_dB = 10 * log10(pxx_sqz_w);
    pxx_coh_w_dB = 10 * log10(pxx_coh_w);

    % 5. 提取绘图频段 (0 到 Nyquist 频率 5 MHz)
    limit_freq = Fs/2; 
    idx = f_w <= limit_freq;
    
    f_plot = f_w(idx) / 1e6; % 将 X 轴转换为 MHz

    % 6. 绘图对比
    figure('Name', '宽带差分噪声功率谱 (AC耦合修正版)', 'Position', [200, 200, 850, 550]);
    plot(f_plot, pxx_coh_w_dB(idx), 'b', 'LineWidth', 1.5); hold on;
    plot(f_plot, pxx_sqz_w_dB(idx), 'r', 'LineWidth', 1.5);
    
    grid on;
    title('AC 耦合后的宽带差分噪声功率谱 (纯涨落)', 'FontSize', 14);
    xlabel('频率 (MHz)', 'FontSize', 12);
    ylabel('噪声功率谱密度 (dB)', 'FontSize', 12);
    legend('相干光差分 (散粒噪声极限, SNL)', '压缩光差分', 'Location', 'best', 'FontSize', 11);
    xlim([0, 5]); 

    % --- 7. 针对 0-1000 Hz 极低频段的高分辨率分析绘图 ---
    % 核心修正：在 10 MHz 的高采样率下，必须使用极其庞大的 NFFT 才能在极低频段获得足够的频率分辨率
    nfft_low = length(diff_sqz_ac); % 直接使用全长数据，获取理论上的极限低频分辨率
    window_low = hann(nfft_low);
    
    [pxx_sqz_low, f_low] = pwelch(diff_sqz_ac, window_low, 0, nfft_low, Fs);
    [pxx_coh_low, ~]   = pwelch(diff_coh_ac, window_low, 0, nfft_low, Fs);
    
    pxx_sqz_low_dB = 10 * log10(pxx_sqz_low);
    pxx_coh_low_dB = 10 * log10(pxx_coh_low);
    
    figure('Name', '极低频段差分噪声 (0-1000 Hz)', 'Position', [250, 250, 850, 550]);
    plot(f_low, pxx_coh_low_dB, 'b', 'LineWidth', 1.5); hold on;
    plot(f_low, pxx_sqz_low_dB, 'r', 'LineWidth', 1.5);
    
    grid on;
    title('原始宽带数据在 0-1000 Hz 频段的噪声暴露', 'FontSize', 14);
    xlabel('频率 (Hz)', 'FontSize', 12);
    ylabel('噪声功率谱密度 (dB)', 'FontSize', 12);
    legend('相干光差分 (SNL)', '压缩光差分', 'Location', 'best');
    xlim([0, 1000]);
    
    disp('第六部分执行完毕。');
end

%% 第三部分：延时效应模拟与前馈压缩观察 (含相干光严谨对照)
% 【执行开关】: true = 执行此部分, false = 直接跳过
run_part3 = 0;   

if run_part3
    disp('正在执行第三部分：模拟延时对量子纠缠及相干光的影响...');
    
    % --- 参数设定 ---
    delay_time = 500e-9; 
    delay_samples = round(delay_time * Fs); % 转换为采样点数
    fprintf('设定的延时时间为: %.1f ns (对应 %d 个采样点)\n', delay_time*1e9, delay_samples);
    
    if delay_samples == 0
        warning('延时过小，当前采样率下无法体现。请增大延时或提高采样率。');
    end
    
    % --- 1. 构建带有延时的数据 (Signal 通道整体向后平移) ---
    % 压缩光延时
    mean_sqz = mean(sqz_signal);
    delayed_sqz = [mean_sqz * ones(delay_samples, 1); sqz_signal(1:end-delay_samples)];
    
    % 相干光延时 (作为严谨对照)
    mean_coh = mean(coh_signal);
    delayed_coh = [mean_coh * ones(delay_samples, 1); coh_signal(1:end-delay_samples)];
    
    % --- 2. 模拟前馈作差 (Idler 减去 Signal) ---
    % 理想情况 (无延时)
    diff_sqz_ideal = sqz_signal - sqz_idler; 
    diff_coh_ideal = coh_signal - coh_idler;
    
    % 实际情况 (有延时：Idler 减去 带有延时的 Signal)
    diff_sqz_delayed = delayed_sqz - sqz_idler; 
    diff_coh_delayed = delayed_coh - coh_idler; 
    
    % --- 3. 计算 PSD ---
    [pxx_sqz_ideal, f3] = pwelch(diff_sqz_ideal, window, noverlap, nfft, Fs);
    [pxx_sqz_delayed, ~] = pwelch(diff_sqz_delayed, window, noverlap, nfft, Fs);
    
    [pxx_coh_ideal, ~] = pwelch(diff_coh_ideal, window, noverlap, nfft, Fs);
    [pxx_coh_delayed, ~] = pwelch(diff_coh_delayed, window, noverlap, nfft, Fs);
    
    % 转换为 dB
    pxx_sqz_ideal_dB = 10 * log10(pxx_sqz_ideal);
    pxx_sqz_delayed_dB = 10 * log10(pxx_sqz_delayed);
    pxx_coh_ideal_dB = 10 * log10(pxx_coh_ideal);
    pxx_coh_delayed_dB = 10 * log10(pxx_coh_delayed);
    
    % --- 4. 提取绘图频段 (0 到 6 MHz) ---
    target_freq = 6e6;
    limit_freq = min(target_freq, Fs/2);
    idx = f3 <= limit_freq;
    
    f_plot3 = f3(idx) / 1e6; % MHz
    
    % --- 5. 绘图对比 ---
    figure('Name', '延时对前馈压缩带宽的影响对比', 'Position', [200, 200, 850, 550]);
    
    % 画出相干光 (基准)
    plot(f_plot3, pxx_coh_ideal_dB(idx), 'k', 'LineWidth', 2); hold on;
    plot(f_plot3, pxx_coh_delayed_dB(idx), 'Color', [0.6 0.6 0.6], 'LineWidth', 1.5, 'LineStyle', '-.');
    
    % 画出压缩光
    plot(f_plot3, pxx_sqz_ideal_dB(idx), 'b', 'LineWidth', 1.5, 'LineStyle', '--');
    plot(f_plot3, pxx_sqz_delayed_dB(idx), 'r', 'LineWidth', 1.5);
    grid on;
    
    title(sprintf('延时 (%.1f ns) 对纠缠光与相干光的影响', delay_time*1e9), 'FontSize', 14);
    xlabel('频率 (MHz)', 'FontSize', 12);
    ylabel('噪声功率谱密度 (dB)', 'FontSize', 12);
    legend('理想相干光作差 (SNL基准)', '延时相干光作差 (完全重合)', ...
           '理想纠缠光作差 (无延时)', '延时纠缠光作差 (实际前馈)', ...
           'Location', 'best', 'FontSize', 11);
    xlim([0, limit_freq/1e6]);
    
    disp('第三部分执行完毕。');
    disp('--------------------------------------------------');
else
    disp('【跳过】第三部分：延时效应模拟。');
end

%% 第四部分：时间关联分析 (高通滤波提取纳秒级量子相关)
run_part4 = 0;   

if run_part4
    disp('正在执行第四部分：计算纳秒级量子涨落互相关函数...');
    
    % --- 1. 设计并应用高通滤波器滤除经典噪声 ---
    % 采样率为 10 MHz，Nyquist 频率为 5 MHz
    % 设定截止频率为 1 MHz，彻底滤除 20kHz, 300kHz 等低频经典和技术噪声
    fc = 1e6; 
    [b, a] = butter(4, fc / (Fs/2), 'high');
    
    % 使用 filtfilt 进行零相移滤波，避免滤波器引入额外的群延迟
    sqz_sig_filt = filtfilt(b, a, sqz_signal);
    sqz_idl_filt = filtfilt(b, a, sqz_idler);
    
    coh_sig_filt = filtfilt(b, a, coh_signal);
    coh_idl_filt = filtfilt(b, a, coh_idler);
    
    % --- 2. 计算归一化互相关函数 ---
    % 聚焦于 100 ns 量级，设置极小的最大延迟点数
    % 取 maxlag = 30，对应 +/- 3000 ns 的时间窗口
    maxlag = 30; 
    
    [r_sqz, lags] = xcorr(sqz_sig_filt, sqz_idl_filt, maxlag, 'coeff');
    [r_coh, ~]    = xcorr(coh_sig_filt, coh_idl_filt, maxlag, 'coeff');
    
    % 将滞后点数 (lags) 转换为时间延迟 (纳秒 ns)
    time_lags_ns = lags * dt * 1e9; 
    
    % --- 3. 提取相干时间特征 (半高全宽 FWHM) ---
    [max_val, max_idx] = max(r_sqz);
    half_max = max_val / 2;
    
    left_idx = find(r_sqz(1:max_idx) <= half_max, 1, 'last');
    right_idx = max_idx + find(r_sqz(max_idx:end) <= half_max, 1, 'first') - 1;
    
    if ~isempty(left_idx) && ~isempty(right_idx)
        tau_c_ns = time_lags_ns(right_idx) - time_lags_ns(left_idx);
    else
        tau_c_ns = NaN; 
    end
    
    % --- 4. 绘图对比 ---
    figure('Name', '时域互相关函数 - 纳秒级量子关联', 'Position', [250, 250, 800, 500]);
    
    plot(time_lags_ns, r_coh, 'k', 'LineWidth', 1.2); hold on;
    % 加入散点标记 '.-'，以便在 100 ns 分辨率下看清每一个离散采样点
    plot(time_lags_ns, r_sqz, 'r.-', 'LineWidth', 1.5, 'MarkerSize', 12);
    
    xline(0, 'k--', 'LineWidth', 1);
    
    grid on;
    title('高频量子涨落互相关函数 (High-pass > 1 MHz)', 'FontSize', 14);
    xlabel('时间延迟 \tau (ns)', 'FontSize', 12);
    ylabel('归一化互相关系数', 'FontSize', 12);
    legend('相干光 (基准：完全不相关)', '压缩光 (纯量子纠缠)', 'Location', 'best', 'FontSize', 11);
    xlim([-maxlag*dt*1e9, maxlag*dt*1e9]);
    
    fprintf('互相关峰值出现在延迟时间: %.1f ns 处\n', time_lags_ns(max_idx));
    if ~isnan(tau_c_ns)
        fprintf('评估得到的纯量子相干时间 (FWHM) 约为: %.1f ns\n', tau_c_ns);
    else
        disp('未能准确评估相干时间 (采样率可能受限)。');
    end
    
    disp('第四部分执行完毕。');
    disp('--------------------------------------------------');
else
    disp('【跳过】第四部分：时间关联分析。');
end

%% 第五部分（真实前馈版）：B 路保持完全不变，仅对 A 路做锁相解调-低通延时-重调制，在 B 路生成特定频段单模压缩光
run_feedback_sim_raw = 0;

if run_feedback_sim_raw
    % ===== 只需在这里修改参数 =====
    f_larmor = 0.5e6;          % 拉莫尔/锁相中心频率，Hz (500 kHz)
    f_lpf = 5000;              % 基带低通 -3 dB 截止频率，Hz (对应射频 500 kHz +/- 5 kHz)
    lpf_order = 4;             % Butterworth 低通阶数
    delay_source = 'both';     % 'none' | 'manual' | 'filter' | 'both'
    delay_time = 0.1e-6;       % 基带人为附加延时，秒；仅 manual/both 使用 (可改为 50e-6 测试)
    gain_mode = 'unity';       % 'unity' (固定增益 g=1) | 'optimal' (按互相关自动计算最优单模压缩增益)
    welch_segment_time = 0.5;  % Welch 谱估计每段期望时长，秒

    % 物理流程说明：
    % 1. B 路 (sqz_sig_ac) 全程保持原始射频时域信号【完全不变】，不进锁相、不滤波、不延时；
    % 2. A 路 (sqz_idl_ac) 经过 500 kHz I/Q 下变频 -> 5 kHz 低通滤波 -> 基带延时 -> 500 kHz I/Q 重调制回射频；
    % 3. 在射频时域直接执行 y_B(t) = B(t) - g * A_remod(t)，在 B 路上生成 495~505 kHz 频段的单模压缩光；
    % 4. 散粒噪声极限 (SNL) 基准严格采用【未经任何处理的单路相干光 B (coh_sig_ac)】，不再用虚高 3 dB 的双路相干光差分。

    assert(Fs > 0 && f_lpf > 0 && f_larmor > f_lpf && ...
        f_larmor + f_lpf < Fs/2, '载频及低通频带必须位于 Nyquist 范围内。');

    % --- 1. 对齐记录长度并做 AC 耦合（去直流） ---
    p5_lengths = [numel(sqz_signal), numel(sqz_idler), ...
        numel(coh_signal), numel(coh_idler)];
    N = min(p5_lengths);
    p5_input = [sqz_signal(1:N), sqz_idler(1:N), coh_signal(1:N), coh_idler(1:N)];
    p5_input = p5_input - mean(p5_input, 1);
    
    sqz_B_raw = p5_input(:,1); % 压缩光 B 路 (目标路，全程保持不变！)
    sqz_A_raw = p5_input(:,2); % 压缩光 A 路 (参考路，进入锁相与前馈处理)
    coh_B_raw = p5_input(:,3); % 相干光 B 路 (真正的单路散粒噪声极限 SNL 基准，全程保持不变！)
    coh_A_raw = p5_input(:,4); % 相干光 A 路 (仅用于对照)
    t = (0:N-1)' / Fs;

    % --- 2. 仅对 A 路做锁相 I/Q 下变频解调（提取 500 kHz 附近包络到基带） ---
    LO_I_demod = 2 * cos(2*pi*f_larmor*t);
    LO_Q_demod = 2 * sin(2*pi*f_larmor*t);
    
    % 只混频 A 路（列 1,2 为压缩光 A 路 I/Q；列 3,4 为相干光 A 路 I/Q）
    p5_A_mixed = [sqz_A_raw .* LO_I_demod, sqz_A_raw .* LO_Q_demod, ...
                  coh_A_raw .* LO_I_demod, coh_A_raw .* LO_Q_demod];

    % --- 3. 对 A 路基带信号进行低通滤波（零相位理想对照 |H| 与因果低通 H） ---
    [p5_z, p5_p, p5_k] = butter(lpf_order, f_lpf/(Fs/2), 'low');
    [p5_sos, p5_filter_gain] = zp2sos(p5_z, p5_p, p5_k);
    p5_settle = max(32, ceil(log(1e-8)/log(max(abs(p5_p)))));
    p5_pad = 2 * p5_settle;
    p5_fft_length = 2^nextpow2(N + 2*p5_pad);
    
    p5_H = p5_filter_gain * ones(p5_fft_length, 1);
    for p5_section = 1:size(p5_sos, 1)
        p5_H = p5_H .* freqz(p5_sos(p5_section,1:3), ...
            p5_sos(p5_section,4:6), p5_fft_length, 'whole');
    end
    p5_magnitude = abs(p5_H);
    p5_magnitude = 0.5 * (p5_magnitude + p5_magnitude([1, end:-1:2]));
    
    % 计算 A 路的零相位低通基带包络（用于理想无延时对照，以及 none/manual 模式）
    p5_A_base_zero = zeros(N, 4);
    for ch = 1:4
        p5_padded = [zeros(p5_pad,1); p5_A_mixed(:,ch); zeros(p5_pad,1)];
        p5_filtered = real(ifft(fft(p5_padded, p5_fft_length) .* p5_magnitude));
        p5_A_base_zero(:,ch) = p5_filtered(p5_pad + (1:N));
    end
    clear p5_padded p5_filtered p5_H p5_magnitude;

    % --- 4. 选择 A 路的滤波器延时与基带人工采样移位 ---
    p5_use_filter_delay = strcmpi(delay_source,'filter') || strcmpi(delay_source,'both');
    if p5_use_filter_delay
        % A 路通过真实因果低通滤波器 sosfilt（包含滤波器相位滞后）
        p5_A_base_sel = p5_filter_gain * sosfilt(p5_sos, p5_A_mixed);
    else
        % A 路使用零相位低通结果
        p5_A_base_sel = p5_A_base_zero;
    end

    if strcmpi(delay_source,'manual') || strcmpi(delay_source,'both')
        delay_samples = round(delay_time * Fs);
    else
        delay_samples = 0;
    end
    p5_actual_delay = delay_samples / Fs;

    % 确定有效稳态时间窗口：p5_now 为当前时刻 t，p5_past 为基带延时后的时刻 t - tau
    p5_first = p5_pad + delay_samples + 1;
    p5_last = N - p5_pad;
    p5_now = (p5_first:p5_last)';
    p5_past = p5_now - delay_samples;
    t_now = t(p5_now);

    % --- 5. 核心步骤：将处理后的基带 A 路【重调制（上变频）】回 500 kHz 射频段 ---
    % 注意：下变频已经乘过系数 2，因此上变频直接乘 cos(2*pi*f_L*t_now) 和 sin(2*pi*f_L*t_now)
    % 关键物理原理：上变频使用的是当前时刻的本振相位 t_now，而包络取自 p5_past，
    % 这准确对应硬件中"本振相位锁定，延时发生在解调后的基带滤波/控制链路中"！
    LO_I_remod = cos(2*pi*f_larmor*t_now);
    LO_Q_remod = sin(2*pi*f_larmor*t_now);

    % (a) 理想零延时 A 路重构射频信号
    sqz_A_rf_ideal = p5_A_base_zero(p5_now,1).*LO_I_remod + p5_A_base_zero(p5_now,2).*LO_Q_remod;
    % (b) 所选延时模式下 A 路重构射频信号（包络来自 p5_past）
    sqz_A_rf_delayed = p5_A_base_sel(p5_past,1).*LO_I_remod + p5_A_base_sel(p5_past,2).*LO_Q_remod;

    % 提取完全未受触动的原始 B 路信号（仅截取相同的时间段 p5_now 做观测）
    sqz_B_untouched = sqz_B_raw(p5_now);
    coh_B_untouched = coh_B_raw(p5_now); % 单路相干光 B 路（1x SNL 绝对基准）

    % --- 6. 在时域上直接对原始 B 路做前馈相减，生成特定频段单模压缩光 ---
    if strcmpi(gain_mode, 'optimal')
        % 自动计算最优前馈增益 g = <B, A_rf> / <A_rf, A_rf>
        g_ideal = (sqz_B_untouched' * sqz_A_rf_ideal) / (sqz_A_rf_ideal' * sqz_A_rf_ideal);
        g_sel   = (sqz_B_untouched' * sqz_A_rf_delayed) / (sqz_A_rf_delayed' * sqz_A_rf_delayed);
    else
        g_ideal = 1.0;
        g_sel   = 1.0;
    end

    % B 路生成的单模压缩光时间序列（射频直接相减！）
    B_single_sqz_ideal   = sqz_B_untouched - g_ideal * sqz_A_rf_ideal;
    B_single_sqz_delayed = sqz_B_untouched - g_sel   * sqz_A_rf_delayed;

    % --- 7. 直接对 B 路信号做 Welch FFT 功率谱分析（观察 500 kHz 附近及边带压缩） ---
    p5_valid_N = numel(p5_now);
    p5_segment_N = min(p5_valid_N, max(128, round(welch_segment_time*Fs)));
    window_narrow = hann(p5_segment_N, 'periodic');
    p5_overlap = floor(p5_segment_N / 2);
    nfft_narrow = 2^nextpow2(p5_segment_N);

    % 直接对这四条真实的射频信号求 PSD：
    % 1. 单路相干光 B (真正的单路 SNL 基准)
    % 2. 未加反馈的原始压缩光单路 B (单束看是热态过剩噪声)
    % 3. 理想零延时前馈后的单路 B (理想单模压缩光)
    % 4. 所选延时前馈后的单路 B (实际单模压缩光)
    [p5_psd_rf, f_rf] = pwelch([coh_B_untouched, sqz_B_untouched, ...
        B_single_sqz_ideal, B_single_sqz_delayed], ...
        window_narrow, p5_overlap, nfft_narrow, Fs);

    psd_snl_single = p5_psd_rf(:,1);
    psd_B_raw      = p5_psd_rf(:,2);
    psd_B_ideal    = p5_psd_rf(:,3);
    psd_B_delayed  = p5_psd_rf(:,4);

    % 相对单路 B 散粒噪声极限 (1x SNL) 的相对噪声功率谱 (dB)
    rel_B_raw_dB     = 10*log10(max(psd_B_raw, realmin)     ./ max(psd_snl_single, realmin));
    rel_B_ideal_dB   = 10*log10(max(psd_B_ideal, realmin)   ./ max(psd_snl_single, realmin));
    rel_B_delayed_dB = 10*log10(max(psd_B_delayed, realmin) ./ max(psd_snl_single, realmin));

    fprintf('\n===== 第五部分（单路 B 保持不变 - 单模压缩光生成模拟）=====\n');
    fprintf('中心频率 %.1f kHz | 低通带宽 +/-%.1f kHz | 模式: %s | 附加延时: %.2f us\n', ...
        f_larmor/1e3, f_lpf/1e3, delay_source, p5_actual_delay*1e6);
    fprintf('前馈增益模式: %s (g_ideal = %.3f, g_selected = %.3f)\n', gain_mode, g_ideal, g_sel);

    % --- 8. 绘图展示：上图看 500 kHz 射频凹陷，下图看相对于 f_larmor 的正负边带/基带偏移 ---
    figure('Name', '单路B生成特定频段单模压缩光 (B路完全不变)', 'Position', [200, 80, 1050, 820]);
    tiledlayout(2, 1, 'TileSpacing', 'compact');

    % 【上图】：射频视角 (观察 485 kHz ~ 515 kHz，看 500 kHz 处挖出的单模压缩凹陷)
    nexttile;
    rf_span = 3 * f_lpf; % 显示正负 15 kHz 范围以看清滤波窗口边界
    idx_rf = f_rf >= (f_larmor - rf_span) & f_rf <= (f_larmor + rf_span);
    f_rf_kHz = f_rf(idx_rf) / 1e3;
    
    plot(f_rf_kHz, rel_B_raw_dB(idx_rf), 'Color', [0.75 0.75 0.75], 'LineWidth', 1); hold on;
    plot(f_rf_kHz, rel_B_ideal_dB(idx_rf), 'b--', 'LineWidth', 1.2);
    plot(f_rf_kHz, rel_B_delayed_dB(idx_rf), 'r-', 'LineWidth', 1.2);
    yline(0, 'k-', 'LineWidth', 1.5, 'Label', '单路 B 散粒噪声极限 (0 dB SNL)');
    xline((f_larmor - f_lpf)/1e3, 'k:', '-5 kHz 截止');
    xline((f_larmor + f_lpf)/1e3, 'k:', '+5 kHz 截止');
    grid on;
    xlim([(f_larmor - rf_span)/1e3, (f_larmor + rf_span)/1e3]);
    xlabel('射频频率 f (kHz)');
    ylabel('相对单路 B 散粒噪声极限 (dB)');
    title(sprintf('B 路射频谱：在 %.0f kHz +/- %.0f kHz 窗口内生成单模压缩光 (B路原始信号未做任何改变)', ...
        f_larmor/1e3, f_lpf/1e3));
    legend('未加反馈的原始 B 路 (热态过剩噪声)', '理想零延时前馈后的 B 路', ...
        sprintf('所选延时 (%s, %.1f us) 前馈后的 B 路', delay_source, p5_actual_delay*1e6), ...
        'Location', 'best');

    % 【下图】：边带对数视角 (将 f_larmor 两侧上/下边带折叠对齐到偏移频率 df = |f - f_larmor|，观察 20 Hz 处)
    nexttile;
    % 取上边带 f > f_larmor 且 f <= f_larmor + f_lpf 的频点观察边带偏移频率 df
    idx_sb = f_rf > f_larmor & f_rf <= (f_larmor + f_lpf);
    df_Hz = f_rf(idx_sb) - f_larmor;
    
    semilogx(df_Hz, rel_B_ideal_dB(idx_sb), 'b--', 'LineWidth', 1.2); hold on;
    semilogx(df_Hz, rel_B_delayed_dB(idx_sb), 'r-', 'LineWidth', 1.2);
    yline(0, 'k-', 'LineWidth', 1.2);
    xline(20, 'k:', '20 Hz 待测边带');
    grid on;
    xlim([max(1, min(df_Hz)), f_lpf]);
    xlabel('偏离拉莫尔载频的边带频率 \Deltaf = f - f_{larmor} (Hz)');
    ylabel('相对单路 B 散粒噪声 (dB)');
    title('拉莫尔上边带 (\Deltaf = 0 ~ 5 kHz) 的单模压缩效果对数视图');
    legend('理想零延时单模压缩', '所选延时模式单模压缩', '0 dB 单路 SNL', 'Location', 'best');
end


% [P6-01] 第六部分入口与参数覆盖
% 保留原第一至第五部分；本部分调用本文件末尾的局部函数，不依赖外部辅助.m。
% 物理计算使用精确cos；增加固定实数增益扫描与带内功率最小化。
% 参数默认取原文件后半段第六部分；run_part_mag_feedback控制本部分是否执行。
%% 第六部分：原非线性模型、固定增益扫描和噪声对照（完整单文件版）
run_part_mag_feedback = 1;
if run_part_mag_feedback
    cfg6 = part6_gain_defaults();
    % 可在下方覆盖默认值；完整默认参数在本文件 [P6-02]。
    % cfg6.gain_grid = -12:0.1:4;          % 一个固定增益用于整个频段
    % cfg6.target_band_Hz = [495e3 505e3]; % 先积分线性PSD，再转换dB
    % cfg6.delay_time = 1e-6;             % 附加基带硬件延时，单位秒
    % cfg6.remove_carrier = false;        % 保留原active设置及Q通道DC偏置
    % cfg6.make_figures = false;          % 仅计算并保存数值，不生成图
    part6_result = part6_gain_scan(sqz_signal,sqz_idler,coh_signal,coh_idler,Fs,cfg6);
    C_fb_use = part6_result.summary.Gain(3);    % 单通道、因果低通、有附加延时
    C_fb_ideal = part6_result.summary.Gain(1);  % 单通道、理想零相位、无电子噪声
    C_fb_use_IQ = part6_result.summary.Gain(6); % 双通道、因果低通、有附加延时
end

%% 第六部分使用的局部函数（全部包含在此文件内）
% 数学说明和定位编号与同包PDF对应。下面局部函数只服务第六部分。
% 以下函数的计算语句与已复核模块版相同，只增加分块解释注释。

% [P6-02] 默认物理参数与增益搜索范围
% f_larmor/f_mod为载波与混频频率；f_lpf为低通截止频率；delay_time是基带附加延时。
% target_band_Hz是评判频段，与滤波参数分开保存；调频率后需同步检查。
% C是代码中的无量纲相位反馈系数，输入相位修正为(C/M)*S_fb。
function cfg = part6_gain_defaults()
% 第六部分可调参数；物理参数取自用户原文件的第二份第六部分。
cfg.f_larmor = 0.5e6;
cfg.f_mod = 0.5e6;
cfg.f_lpf = 5000;
cfg.lpf_order = 4;
cfg.delay_time = 1e-6;
cfg.delay_scan_us = [0 0.1 0.5 1 1.5];
cfg.elec_noise_ratio = 0.10;
cfg.M_cell_ratio = 10;
cfg.phi_idler_0 = -pi/2;
cfg.phi_sig_0 = -pi/2;
cfg.phi_demod = 0;
cfg.remove_carrier = false; % 原active代码为0；保留进入反馈回路的载波/DC偏置
cfg.mag_noise_ratio = 0.8;
cfg.f_mag_bw = 1500;
cfg.welch_seg_time = 0.005;
cfg.seed = 42;
% 一个固定的实数增益用于整个频段；不逐频点任意选择增益。
cfg.target_band_Hz = [cfg.f_larmor-cfg.f_lpf, cfg.f_larmor+cfg.f_lpf];
cfg.gain_grid = -12:0.1:4; % 包含0；全区间扫描，然后细化每一个网格局部极小值
cfg.gain_tol = 1e-5;
cfg.make_figures = true;
cfg.figure_visible = 'on';
cfg.output_dir = fullfile(fileparts(mfilename('fullpath')), 'results');
end


% [P6-03] 输入检查与零增益候选
% 检查采样率、频段、噪声幅度与扫描网格；加入C=0，保证无反馈也是可选方案。
function result = part6_gain_scan(sqz_signal,sqz_idler,coh_signal,coh_idler,Fs,cfg)
% 在用户第六部分的精确非线性cos模型外增加增益搜索，不用线性化代替输出。
% J(C)=目标频段内Welch PSD积分 / 同频段单路相干记录PSD积分。
% 每个模型/滤波延时场景分别优化一个固定实数C。所有增益复用相同随机噪声。
% 噪声评价减去同C的零随机输入确定性参考；原始光路输出仍保留载波。
if nargin<6, cfg=part6_gain_defaults(); end
assert(isfinite(Fs)&&Fs>0,'Fs必须为正。');
assert(cfg.M_cell_ratio>0 && cfg.delay_time>=0 && all(cfg.delay_scan_us>=0));
assert(cfg.target_band_Hz(1)>0 && cfg.target_band_Hz(2)<Fs/2 && diff(cfg.target_band_Hz)>0);
assert(cfg.f_lpf>0 && cfg.f_lpf<Fs/2 && cfg.f_mag_bw>0 && cfg.f_mag_bw<Fs/2);
assert(cfg.mag_noise_ratio>=0 && cfg.elec_noise_ratio>=0);
assert(isvector(cfg.gain_grid)&&numel(cfg.gain_grid)>=3&&all(isfinite(cfg.gain_grid)));
cfg.gain_grid=unique([cfg.gain_grid(:);0]);
if ~exist(cfg.output_dir,'dir'), mkdir(cfg.output_dir); end

% [P6-04] 四路对齐、AC耦合与相干尺度
% 共同长度取四路最短；每路减自身均值。sigma来自单路相干数据，M=M_cell_ratio*sigma。
% Ns/Ni是记录的全部交流涨落，不能仅凭命名视为纯量子噪声。
N=min([numel(sqz_signal),numel(sqz_idler),numel(coh_signal),numel(coh_idler)]);
X=[sqz_signal(1:N),sqz_idler(1:N),coh_signal(1:N),coh_idler(1:N)];
assert(size(X,1)==N&&all(isfinite(X(:))), '四路输入必须为有限数值列向量，禁止静默删除样本。');
X=X-mean(X,1); Ns=X(:,1); Ni=X(:,2); Cs=X(:,3); Ci=X(:,4); clear X
t=(0:N-1)'/Fs; sigma=std(Cs); assert(sigma>0,'相干参考不能为常数。');
M=cfg.M_cell_ratio*sigma;

% [P6-05] 固定随机实现与模拟磁相位噪声
% 白噪声经二阶filtfilt后按std归一化，再乘mag_noise_ratio*sigma*sqrt(2*f_lpf/Fs)/M。
% 所有增益共享同一磁噪声；这里直接生成相位Phi，没有另解原子动力学。
rng_before=rng; restore_rng=onCleanup(@()rng(rng_before)); %#ok<NASGU>
rng(cfg.seed,'twister');
% 以下磁噪声构造、cos调制、混频、Butterworth滤波均沿用原第六部分。
if cfg.mag_noise_ratio>0
    [bm,am]=butter(2,cfg.f_mag_bw/(Fs/2),'low');
    raw=filtfilt(bm,am,randn(N,1)); raw=raw/std(raw);
    Phi=cfg.mag_noise_ratio*sigma*sqrt(2*cfg.f_lpf/Fs)/M*raw;
else
    Phi=zeros(N,1);
end

% [P6-06] Idler精确非线性磁光调制
% 构造M*cos(theta_i+Phi)，按remove_carrier决定是否先在idler侧扣去静态载波。
% 默认false：进入反馈回路的载波保持原样，尤其Q混频的直流偏置保留。
theta_i=2*pi*cfg.f_larmor*t+cfg.phi_idler_0;
carrier_i=M*cos(theta_i);
cell_i=M*cos(theta_i+Phi);
if cfg.remove_carrier
    cell_i=cell_i-carrier_i; carrier_i=zeros(N,1);
end

% [P6-07] I/Q混频与两种Butterworth低通
% 四列同时处理：压缩光、相干光、无新增磁噪声光学记录、零随机输入确定性参考。
% sosfilt是因果滤波；filtfilt是离线零相位对照且等效幅频响应平方。
mixcos=cos(2*pi*cfg.f_mod*t+cfg.phi_demod);
mixsin=sin(2*pi*cfg.f_mod*t+cfg.phi_demod);
[z,p,k]=butter(cfg.lpf_order,cfg.f_lpf/(Fs/2),'low');
[sos,g]=zp2sos(z,p,k);
% 四列：实际idler；相干idler(同经典磁噪声)；无新增磁噪声idler；确定性idler。
input=[Ni+cell_i,Ci+cell_i,Ni+carrier_i,carrier_i];
BI=struct(); BQ=struct();
BI.ideal=filtfilt(sos,g,input.*mixcos); BQ.ideal=filtfilt(sos,g,input.*mixsin);
BI.causal=g*sosfilt(sos,input.*mixcos); BQ.causal=g*sosfilt(sos,input.*mixsin);
clear input mixcos mixsin cell_i carrier_i raw

% [P6-08] 电子白噪声与统一稳态取样窗口
% 电子噪声在低通后相加，代码没有对它再次低通；sqrt(f_lpf/Fs)只设置幅度尺度。
% 由滤波极点估算瞬态衰减时间，两端统一截去边界，最大延时也纳入前端裁剪。
std_e=cfg.elec_noise_ratio*sigma*sqrt(cfg.f_lpf/Fs);
ei=std_e*randn(N,1); eq=std_e*randn(N,1);
% 稳态窗口两端均去掉建立/边界段；所有增益/模型/延时完全相同。
settle=max(64,2*ceil(log(1e-6)/log(max(abs(p)))));
delay_pts=round(cfg.delay_time*Fs);
maxdelay=max([delay_pts,round(cfg.delay_scan_us*1e-6*Fs)]);
idx=(settle+maxdelay+1:N-settle)';
assert(numel(idx)>=16384,'记录过短，无法在滤波器稳定后做可靠Welch估计。');

% [P6-09] Welch分段和相干频段参考
% 周期Hann窗、50%重叠、固定FFT网格；参考功率是相干PSD在目标频段的线性积分。
% FFT频点间隔与Hann窗ENBW不是同一量，补零不提高真实分辨率。
L=numel(idx);
seg=min(floor(L/4),max(4096,round(cfg.welch_seg_time*Fs)));
spec.win=hann(seg,'periodic'); spec.ov=floor(seg/2);
spec.nfft=max(16384,2^nextpow2(seg)); spec.Fs=Fs;
[Psnl,f]=pwelch(Cs(idx),spec.win,spec.ov,spec.nfft,Fs);
spec.f=f; spec.band=cfg.target_band_Hz;
spec.snl=band_integral(Psnl,spec); assert(spec.snl>0);
fprintf('\n第六部分：%d点；评价窗口%.3f ms；频段 %.3f--%.3f kHz\n',N,L/Fs*1e3,cfg.target_band_Hz/1e3);
fprintf('增益范围 [%.3f, %.3f]，%d个粗扫描点；分段 %.3f ms，ENBW %.1f Hz\n', ...
    min(cfg.gain_grid),max(cfg.gain_grid),numel(cfg.gain_grid),seg/Fs*1e3,Fs*sum(spec.win.^2)/sum(spec.win)^2);

% [P6-10] 无反馈基线与诊断基线
% 无反馈噪声为Ns+M[cos(theta+Phi)-cos(theta)]；已排除确定性载波。
% 另存同磁扰动相干基线、无新增磁噪声光学PSD、磁扰动响应PSD。
base.theta=2*pi*cfg.f_larmor*t(idx)+cfg.phi_sig_0;
base.phi=Phi(idx); base.M=M; base.remove_carrier=cfg.remove_carrier;
base.Ns=Ns(idx); base.Cs=Cs(idx);
no_fb=base.Ns+M*(cos(base.theta+base.phi)-cos(base.theta));
coh_no_fb=base.Cs+M*(cos(base.theta+base.phi)-cos(base.theta));
Pno=psd_of(no_fb,spec); Pcohno=psd_of(coh_no_fb,spec);
Pno_nomag=psd_of(base.Ns,spec);
Pno_mag=psd_of(no_fb-base.Ns,spec);

% [P6-11] 两种模型、三种场景与各自最优增益
% 每个组合分别优化压缩光与相干光；同时保留相干同增益对照。
% 总噪声、无新增磁噪声响应及差波形PSD都用同一观测窗；交叉功率单独记录。
% 每次检查C=0是否还原无反馈、最优值是否不劣于C=0、最终PSD积分是否一致。
scenario={'ideal_zero_phase','causal_zero_delay','causal_with_delay'};
models={'single_I','dual_IQ'};
results=cell(2,3); rows=struct([]); scan_rows=table();
for model=1:2
    for s=1:3
        c=make_case(base,BI,BQ,ei,eq,idx,s,delay_pts,model);
        fprintf('优化 %s / %s ...\n',models{model},scenario{s});
        objective=@(gain)score(gain,c,'sqz',spec);
        [best,gridJ,search]=search_gain(objective,cfg);
        % 同回路相干对照也独立搜索；主PSD图另外给出量子最优增益下的相干输出。
        [bestcoh,gridC,searchcoh]=search_gain(@(gain)score(gain,c,'coh',spec),cfg);
        [noise,raw_out,ref_out]=output_model(best,c,'sqz');
        noise_coh=output_model(best,c,'coh');
        noise_coh_opt=output_model(bestcoh,c,'coh');
        noise_nomag=output_model(best,c,'nomag');
        P=psd_of(noise,spec); Pc=psd_of(noise_coh,spec);
        Pco=psd_of(noise_coh_opt,spec); Pnm=psd_of(noise_nomag,spec);
        Pmag=psd_of(noise-noise_nomag,spec);
        Pr=psd_of(raw_out,spec); Pref=psd_of(ref_out,spec);
        total=band_integral(P,spec); optical=band_integral(Pnm,spec); mag=band_integral(Pmag,spec);
        r.Model=string(models{model}); r.Scenario=string(scenario{s});
        r.Gain=best; r.CoherentOptimalGain=bestcoh;
        r.Delay_us=double(s==3)*delay_pts/Fs*1e6;
        r.TotalBandPower=total; r.SNLBandPower=spec.snl;
        r.NoFeedback_dB=db(band_integral(Pno,spec)/spec.snl);
        r.Feedback_dB=db(total/spec.snl);
        r.ReductionFromNoFeedback_dB=db(total/band_integral(Pno,spec));
        r.CoherentSameGain_dB=db(band_integral(Pc,spec)/spec.snl);
        r.CoherentOwnOptimum_dB=db(band_integral(Pco,spec)/spec.snl);
        r.BelowReference=total<spec.snl;
        r.WithoutAddedMag_dB=db(optical/spec.snl);
        r.AddedMagResponse_dB=db(mag/spec.snl);
        r.CrossBandPower=total-optical-mag;
        r.BoundaryOptimum=search.boundary; r.CoherentBoundary=searchcoh.boundary;
        r.SearchRefinementDelta=search.refinement_delta;
        r.FeedbackPhaseI_RMS_rad=std(best*c.I(:,1)/M);
        r.FeedbackPhaseQ_Mean_rad=mean(best*c.Q(:,1)/M)*double(model==2);
        % 两段记录上的固定增益表现：只是稳健性诊断，不伪称独立留出验证。
        mid=floor(L/2);
        r.FirstHalf_dB=half_score(noise(1:mid),base.Cs(1:mid),spec);
        r.SecondHalf_dB=half_score(noise(mid+1:end),base.Cs(mid+1:end),spec);
        if isempty(rows), rows=r; else, rows(end+1)=r; end %#ok<AGROW>
        item.gain=best; item.coh_gain=bestcoh; item.grid_sqz=gridJ; item.grid_coh=gridC;
        item.psd=P; item.psd_coh_same=Pc; item.psd_coh_opt=Pco;
        item.psd_without_mag=Pnm; item.psd_mag_response=Pmag;
        item.psd_raw=Pr; item.psd_deterministic=Pref;
        item.search=search; item.search_coh=searchcoh;
        item.gain_zero_error=max(abs(output_model(0,c,'sqz')-no_fb));
        assert(item.gain_zero_error<1e-10*max(1,max(abs(no_fb))),'零增益未还原无反馈输出。');
        assert(total<=band_integral(Pno,spec)*(1+1e-9),'最优值比零增益差。');
        % 验证扫描器计分与最终全谱积分一致。
        assert(abs(objective(best)-total/spec.snl)<1e-10);
        results{model,s}=item;
        st=table(repmat(string(models{model}),numel(cfg.gain_grid),1), ...
            repmat(string(scenario{s}),numel(cfg.gain_grid),1),cfg.gain_grid,gridJ,gridC, ...
            'VariableNames',{'Model','Scenario','Gain','SqzPowerRatio','CoherentPowerRatio'});
        scan_rows=[scan_rows;st]; %#ok<AGROW>
        fprintf(' C*=%.7f, 噪声 %.4f dB, 相干同增益 %.4f dB, 相干自身最优 %.4f dB\n', ...
            best,r.Feedback_dB,r.CoherentSameGain_dB,r.CoherentOwnOptimum_dB);
    end
end

% [P6-12] 固定增益的硬件延时扫描
% 将C固定为因果低通且零附加延时的最优值，再改变延时样本数。
% 该图不重新调增益，因此可观察同一个控制器面对不同附加延时的变化。
% 额外延时扫描：固定τ=0的最优增益，看硬件延时自身造成的影响，不偷偷重调增益。
delay_rows=struct([]); delay_psd=cell(2,numel(cfg.delay_scan_us));
for model=1:2
    for d=1:numel(cfg.delay_scan_us)
        dp=round(cfg.delay_scan_us(d)*1e-6*Fs);
        c=make_case(base,BI,BQ,ei,eq,idx,3,dp,model);
        gd=results{model,2}.gain;
        Pd=psd_of(output_model(gd,c,'sqz'),spec); delay_psd{model,d}=Pd;
        dr.Model=string(models{model}); dr.RequestedDelay_us=cfg.delay_scan_us(d);
        dr.ActualDelay_us=dp/Fs*1e6; dr.FixedGain=gd;
        dr.Noise_dB=db(band_integral(Pd,spec)/spec.snl);
        if isempty(delay_rows), delay_rows=dr; else, delay_rows(end+1)=dr; end %#ok<AGROW>
    end
end

% [P6-13] 数值、频谱与图像导出
% 完整结果保存在MAT；CSV记录增益扫描、最优值和频谱，中文报告由已算PSD生成。
% 原始含载波PSD和确定性参考PSD均保留，便于排查扣载波前后的差别。
result.config=cfg; result.Fs=Fs; result.input_length=N; result.evaluation_index=[idx(1),idx(end)];
result.segment_length=seg; result.segment_count=1+floor((L-seg)/(seg-spec.ov));
result.fft_spacing_Hz=Fs/spec.nfft; result.ENBW_Hz=Fs*sum(spec.win.^2)/sum(spec.win)^2;
result.f_Hz=f; result.psd_snl=Psnl; result.psd_no_feedback=Pno; result.psd_coh_no_feedback=Pcohno;
result.psd_no_feedback_without_mag=Pno_nomag; result.psd_no_feedback_mag_response=Pno_mag;
result.summary=struct2table(rows); result.scans=scan_rows; result.cases=results;
result.delay_summary=struct2table(delay_rows); result.delay_psd=delay_psd;
result.notes=['Minimum over configured gain range, refined on exact cos model. ', ...
    'Noise excludes the deterministic same-gain zero-random-input output. ', ...
    'SNL is the supplied coherent record, not independently calibrated. ', ...
    'WithoutAddedMag still contains measured optical technical noise and electronic noise.'];
writetable(result.summary,fullfile(cfg.output_dir,'optimal_gains.csv'));
writetable(scan_rows,fullfile(cfg.output_dir,'gain_scan.csv'));
writetable(result.delay_summary,fullfile(cfg.output_dir,'delay_scan.csv'));
% 频谱导出限定为绘图/目标附近频段，完整全谱保存在MAT。
sel=f>=cfg.f_larmor-3*cfg.f_lpf & f<=cfg.f_larmor+3*cfg.f_lpf;
T=table(f(sel),Psnl(sel),Pno(sel),Pcohno(sel),'VariableNames',{'Frequency_Hz','CoherentReference_PSD','NoFeedback_PSD','CoherentNoFeedback_PSD'});
for model=1:2
    for s=1:3
        tag=sprintf('M%d_S%d',model,s); it=results{model,s};
        T.([tag '_Noise_PSD'])=it.psd(sel);
        T.([tag '_CohSameGain_PSD'])=it.psd_coh_same(sel);
        T.([tag '_CohOwnOpt_PSD'])=it.psd_coh_opt(sel);
        T.([tag '_RawWithCarrier_PSD'])=it.psd_raw(sel);
    end
end
writetable(T,fullfile(cfg.output_dir,'noise_spectra.csv'));
save(fullfile(cfg.output_dir,'part6_gain_results.mat'),'result','-v7');
part6_gain_report(result);
if cfg.make_figures, part6_gain_plots(result); end
disp(result.summary(:,{'Model','Scenario','Gain','Feedback_dB','CoherentSameGain_dB','CoherentOwnOptimum_dB'}));
fprintf('已保存到：%s\n',cfg.output_dir);
end


% [P6-14] 场景选取与整数样本延时
% 理想分支用filtfilt且关闭电子噪声；两种因果分支用相同电子噪声。
% past=idx-dp仅延迟低通基带，signal端载波仍取当前theta，不是整条RF信号延迟。
function c=make_case(base,BI,BQ,ei,eq,idx,s,dp,model)
c=base; c.model=model;
if s==1
    c.I=BI.ideal(idx,:); c.Q=BQ.ideal(idx,:); % 沿用原理想对照：无电子噪声
else
    if s==2, dp=0; end
    ip=idx-dp;
    c.I=BI.causal(ip,:); c.Q=BQ.causal(ip,:);
    c.I(:,1:3)=c.I(:,1:3)+ei(ip); c.Q(:,1:3)=c.Q(:,1:3)+eq(ip);
end
end


% [P6-15] 精确cos输出与同增益确定性参考扣除
% 单I：Ns+M*cos(theta+Phi+C*I/M)。双IQ另加M*cos(theta-pi/2+C*Q/M)。
% ref取同C、同滤波和延时，但光学随机量、Phi与电子随机量均为零。
% noise=y-ref只用于评价；不改变进入回路的反馈I/Q，也不作泰勒近似。
function [noise,y,ref]=output_model(gain,c,kind)
switch kind
    case 'sqz', col=1; N=c.Ns; phi=c.phi;
    case 'coh', col=2; N=c.Cs; phi=c.phi;
    case 'nomag', col=3; N=c.Ns; phi=zeros(size(c.phi));
end
% 与原模型A/B相同：反馈直接进入cos内部，绝不做泰勒展开。
y=N+c.M*cos(c.theta+phi+gain/c.M*c.I(:,col));
ref=c.M*cos(c.theta+gain/c.M*c.I(:,4));
if c.model==2
    y=y+c.M*cos(c.theta-pi/2+gain/c.M*c.Q(:,col));
    ref=ref+c.M*cos(c.theta-pi/2+gain/c.M*c.Q(:,4));
end
if c.remove_carrier
    carrier=c.M*cos(c.theta);
    if c.model==2, carrier=carrier+c.M*cos(c.theta-pi/2); end
    y=y-carrier; ref=ref-carrier;
end
noise=y-ref;
end


% [P6-16] 功率谱密度估计
% pwelch返回单边PSD；所有候选使用同一个窗、重叠、NFFT和采样率。
function P=psd_of(x,s)
P=pwelch(x,s.win,s.ov,s.nfft,s.Fs);
end


% [P6-17] 精确频带端点的梯形积分
% 在495/505kHz等指定边界做线性插值，再trapz，避免边界随频点取整漂移。
function p=band_integral(P,s)
% 在指定端点插值再积分，边界不会随FFT频点舍入漂移。
inside=s.f>s.band(1)&s.f<s.band(2);
ff=[s.band(1);s.f(inside);s.band(2)];
pp=[interp1(s.f,P,s.band(1));P(inside);interp1(s.f,P,s.band(2))];
p=trapz(ff,pp);
end


% [P6-18] 优化目标函数
% J(C)=P_signal_band(C)/P_coherent_band；分母固定，等价于最小化signal总带内功率。
function J=score(gain,c,kind,s)
J=band_integral(psd_of(output_model(gain,c,kind),s),s)/s.snl;
end


% [P6-19] 全网格扫描、局部细化和半步核验
% 精算每一个粗网格增益，对各网格局部极小值使用fminbnd，再检查半步网格。
% 记录是否落在边界；它是设定区间内数值最优搜索，不是无界全局最优证明。
function [best,J,info]=search_gain(fun,cfg)
x=cfg.gain_grid; J=zeros(size(x));
for n=1:numel(x), J(n)=fun(x(n)); end
assert(all(isfinite(J))&&all(J>=0),'增益扫描出现无效噪声功率。');
[minJ,at]=min(J); best=x(at); coarse=minJ;
local=find(J(2:end-1)<=J(1:end-2)&J(2:end-1)<=J(3:end))+1;
opt=optimset('TolX',cfg.gain_tol,'Display','off');
for n=local(:)'
    [xx,jj]=fminbnd(fun,x(n-1),x(n+1),opt);
    if jj<minJ, minJ=jj; best=xx; end
end
% 以半步网格核验；若发现粗网格遗漏的更好候选，则重新细化该区间。
half=(x(1:end-1)+x(2:end))/2;
Jh=zeros(size(half));
for n=1:numel(half), Jh(n)=fun(half(n)); end
for n=find(Jh<minJ)'
    [xx,jj]=fminbnd(fun,x(n),x(n+1),opt);
    if jj<minJ, minJ=jj; best=xx; end
end
info.boundary=abs(best-x(1))<=cfg.gain_tol||abs(best-x(end))<=cfg.gain_tol;
info.refinement_delta=coarse-minJ;
info.objective=minJ; info.midpoint_gains=half; info.midpoint_scores=Jh;
info.refined_local_minima=numel(local);
if info.boundary
    warning('最佳增益%.6g落在搜索边界；应扩大gain_grid，不能宣称全局最优。',best);
end
end


% [P6-20] 功率比转dB及前后半段诊断
% 按10*log10(功率比)输出；半段指标只复查已选增益，不是独立留出验证。
function d=db(x)
d=10*log10(max(x,realmin));
end

function value=half_score(x,ref,s)
% 固定同样的窗、频率网格，各半段独立做Welch平均。
value=db(band_integral(psd_of(x,s),s)/band_integral(psd_of(ref,s),s));
end


% [P6-21] 中文数值报告
% 从保存的PSD再次积分生成中文表述；报告新增磁噪声响应、原始光学涨落变化及交叉项。
function part6_gain_report(result)
% 生成人可读的中文结果，始终由保存的线性PSD积分得到。
R=result; f=R.f_Hz; b=R.config.target_band_Hz;
fb=[b(1);f(f>b(1)&f<b(2));b(2)];
bp=@(P)trapz(fb,interp1(f,P,fb));
ref=bp(R.psd_snl); todb=@(x)10*log10(max(x,realmin));
optical0=todb(bp(R.psd_no_feedback_without_mag)/ref);
mag0=todb(bp(R.psd_no_feedback_mag_response)/ref);
coh0=todb(bp(R.psd_coh_no_feedback)/ref);
file=fullfile(R.config.output_dir,'计算结果.txt');
fid=fopen(file,'w','n','UTF-8'); assert(fid>=0); finish=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'第六部分实测数据驱动模拟结果\n\n');
fprintf(fid,'频段：%.3f–%.3f kHz；增益搜索范围：[%.3f, %.3f]。\n',b/1e3,min(R.config.gain_grid),max(R.config.gain_grid));
fprintf(fid,'输入每路%d点，Fs=%.3f MHz；有效窗口%.4f ms；Welch %d段，ENBW %.1f Hz。\n', ...
    R.input_length,R.Fs/1e6,diff(R.evaluation_index)/R.Fs*1e3+1e3/R.Fs,R.segment_count,R.ENBW_Hz);
fprintf(fid,'所有dB相对所给单路相干记录的同频段积分功率。0dB不作独立绝对SNL标定。\n');
fprintf(fid,'未反馈signal（含模拟磁噪声）：%+.6f dB。\n',R.summary.NoFeedback_dB(1));
fprintf(fid,'未反馈相干光（含相同模拟磁噪声）：%+.6f dB。\n',coh0);
fprintf(fid,'未反馈原始光学涨落（无新增磁噪声）：%+.6f dB。\n',optical0);
fprintf(fid,'未反馈的新增磁噪声响应：%+.6f dB。\n\n',mag0);
mn={'单通道I','双通道I/Q'};
sn={'理想零相位、无电子噪声','因果低通、无附加硬件延时','因果低通、有附加硬件延时'};
for m=1:2
    for s=1:3
        r=R.summary((m-1)*3+s,:);
        fprintf(fid,'%s / %s\n',mn{m},sn{s});
        fprintf(fid,'  最佳增益 C = %.9f；附加延时 %.3f us。\n',r.Gain,r.Delay_us);
        fprintf(fid,'  反馈噪声 %+.6f dB；相对无反馈降低 %.6f dB。\n',r.Feedback_dB,-r.ReductionFromNoFeedback_dB);
        fprintf(fid,'  相干光同增益：%+.6f dB；相干光自身最优：%+.6f dB（C=%.9f）。\n', ...
            r.CoherentSameGain_dB,r.CoherentOwnOptimum_dB,r.CoherentOptimalGain);
        fprintf(fid,'  无新增磁噪声时：%+.6f dB（相比原始光学涨落变化 %+.6f dB）。\n', ...
            r.WithoutAddedMag_dB,r.WithoutAddedMag_dB-optical0);
        fprintf(fid,'  新增磁扰动响应：%+.6f dB（相比无反馈变化 %+.6f dB）。\n', ...
            r.AddedMagResponse_dB,r.AddedMagResponse_dB-mag0);
        fprintf(fid,'  交叉功率项 %.9g；是否低于所给相干参考：%d；是否边界最优：%d。\n\n', ...
            r.CrossBandPower,r.BelowReference,r.BoundaryOptimum);
    end
end
[~,which]=min(R.summary.Feedback_dB([3,6])); rows=[3,6]; row=R.summary(rows(which),:);
fprintf(fid,'在本次两种实际有延时结构中，%s 的结果较低，C=%.9f。\n',mn{which},row.Gain);
if ~any(R.summary.BelowReference)
    fprintf(fid,'本次全部六种最优结果均未低于所给相干参考，且仍高于各自相干反馈对照。\n');
end
fprintf(fid,['因果低通条件下，最小化总噪声主要降低了模拟磁噪声响应；关闭新增磁噪声的对照\n', ...
    '仍包含测量中的技术噪声及电子噪声，不能解释为量子噪声的独立测量。\n', ...
    '经典扰动响应与无新增磁噪声对照存在交叉项，二者功率不能直接相加。\n', ...
    '理想filtfilt对照还改变幅频响应并关闭电子噪声，与因果分支的差异不是纯硬件延时效应。\n', ...
    '原始非线性光路保留，PSD评价扣除同增益的零随机输入确定性轨迹，以免将载波当噪声。\n']);
end


% [P6-22] 四组图像及可编辑FIG
% 图1：反馈前后及相干对照；图2：完整增益扫描；图3：模拟磁扰动响应；图4：固定增益延时扫描。
% 逐频点PSD比只用于展示，选择增益使用频段内线性积分；不额外平滑或重调数值。
function part6_gain_plots(result)
% 绘制已计算的第六部分结果，不重新优化，不平滑或改变频谱数据。
% 所有积分dB均来自summary；频谱dB只用于逐频率展示。
cfg=result.config; out=cfg.output_dir;
if ~exist(out,'dir'), mkdir(out); end
visible='on'; if isfield(cfg,'figure_visible'), visible=cfg.figure_visible; end
f=result.f_Hz(:); ref=result.psd_snl(:);
band=cfg.target_band_Hz/1e3;
span=[cfg.f_larmor-3*cfg.f_lpf,cfg.f_larmor+3*cfg.f_lpf]/1e3;
sel=f/1e3>=span(1) & f/1e3<=span(2); x=f(sel)/1e3;
model_names={'Single I channel','Dual I/Q channels'};
scenario_names={'Ideal: zero phase, no electronics','Causal LPF, no added delay', ...
    sprintf('Causal LPF, %.2f us delay',round(cfg.delay_time*result.Fs)/result.Fs*1e6)};
colors=[0.12 0.38 0.72;0.05 0.55 0.50;0.82 0.24 0.15];
gray=[0.48 0.50 0.53]; purple=[0.55 0.30 0.68]; gold=[0.65 0.48 0.10];

fig=newfigure('Noise comparison',[90 70 1300 1020],visible);
tl=tiledlayout(fig,2,1,'TileSpacing','loose','Padding','compact');
title(tl,'Signal noise after idler feedback','FontSize',18,'FontWeight','bold');
subtitle(tl,sprintf('Exact nonlinear cos model | target %.1f–%.1f kHz | deterministic carrier reference removed',band),'FontSize',11);
for m=1:2
    ax=nexttile(tl); hold(ax,'on');
    plot(ax,x,relative(result.psd_no_feedback(sel),ref(sel)),'Color',gray,'LineWidth',1.4,'DisplayName','No feedback');
    for s=1:3
        it=result.cases{m,s}; style='-'; if s==1, style='--'; end
        plot(ax,x,relative(it.psd(sel),ref(sel)),'Color',colors(s,:),'LineStyle',style, ...
            'LineWidth',1.5,'DisplayName',scenario_names{s});
    end
    it=result.cases{m,3};
    plot(ax,x,relative(it.psd_coh_same(sel),ref(sel)),'Color',purple,'LineWidth',1.3, ...
        'LineStyle','-.','DisplayName','Coherent, same gain + delay');
    plot(ax,x,relative(it.psd_coh_opt(sel),ref(sel)),'Color',gold,'LineWidth',1.3, ...
        'LineStyle',':','DisplayName','Coherent, own optimum + delay');
    reference_lines(ax,band); style_axes(ax,span);
    row=result.summary((m-1)*3+3,:);
    title(ax,{model_names{m},sprintf('Delayed optimum C = %.5f | integrated noise %.3f dB | no feedback %.3f dB', ...
        row.Gain,row.Feedback_dB,row.NoFeedback_dB)},'FontSize',12,'FontWeight','normal');
    xlabel(ax,'Frequency (kHz)'); ylabel(ax,'PSD / supplied coherent PSD (dB)');
    legend(ax,'Location','eastoutside','FontSize',10,'Interpreter','none');
end
savefigure(fig,out,'noise_comparison');

fig=newfigure('Gain scan',[110 90 1400 1040],visible);
tl=tiledlayout(fig,2,2,'TileSpacing','loose','Padding','compact');
title(tl,sprintf('Fixed feedback gain optimization over %.1f–%.1f kHz',band),'FontSize',18,'FontWeight','bold');
subtitle(tl,'Linear PSD is integrated before conversion to dB; circles mark refined minima within the search interval','FontSize',11);
for m=1:2
    for kind=1:2
        ax=nexttile(tl); hold(ax,'on');
        for s=1:3
            it=result.cases{m,s}; row=result.summary((m-1)*3+s,:);
            if kind==1
                y=it.grid_sqz; gain=it.gain; val=row.Feedback_dB;
            else
                y=it.grid_coh; gain=it.coh_gain; val=row.CoherentOwnOptimum_dB;
            end
            plot(ax,cfg.gain_grid,todb(y),'Color',colors(s,:),'LineWidth',1.6, ...
                'DisplayName',sprintf('%s | C*=%.4f',short_scenario(s,cfg,result.Fs),gain));
            plot(ax,gain,val,'o','Color',colors(s,:),'MarkerFaceColor','white', ...
                'MarkerSize',7,'LineWidth',1.6,'HandleVisibility','off');
        end
        yline(ax,0,'k:','Supplied coherent reference','HandleVisibility','off','LabelHorizontalAlignment','left');
        xline(ax,0,':','Color',[0.65 0.65 0.65],'HandleVisibility','off');
        style_axes(ax,[min(cfg.gain_grid),max(cfg.gain_grid)]);
        if kind==1, light='Squeezed-light record'; else, light='Coherent-light record'; end
        title(ax,{model_names{m},light},'FontWeight','normal','FontSize',12);
        xlabel(ax,'Feedback gain C'); ylabel(ax,'Integrated band power / reference (dB)');
        legend(ax,'Location','northoutside','FontSize',9,'Interpreter','none');
    end
end
savefigure(fig,out,'gain_scan');

fig=newfigure('Added magnetic noise diagnostic',[130 110 1300 1020],visible);
tl=tiledlayout(fig,2,1,'TileSpacing','loose','Padding','compact');
title(tl,'Response to the added magnetic noise','FontSize',18,'FontWeight','bold');
subtitle(tl,'Delayed optimum in each model; the curves are not an additive PSD budget because cross terms remain','FontSize',11);
for m=1:2
    ax=nexttile(tl); hold(ax,'on'); it=result.cases{m,3}; row=result.summary((m-1)*3+3,:);
    plot(ax,x,relative(it.psd(sel),ref(sel)),'Color',colors(3,:),'LineWidth',1.6,'DisplayName','Total output noise');
    plot(ax,x,relative(it.psd_without_mag(sel),ref(sel)),'Color',colors(1,:),'LineWidth',1.5, ...
        'LineStyle','--','DisplayName','Same gain, no added magnetic noise');
    plot(ax,x,relative(it.psd_mag_response(sel),ref(sel)),'Color',colors(2,:),'LineWidth',1.5, ...
        'DisplayName','Change caused by added magnetic noise');
    plot(ax,x,relative(result.psd_no_feedback_mag_response(sel),ref(sel)),'Color',gray,'LineWidth',1.2, ...
        'LineStyle',':','DisplayName','Magnetic-noise response, no feedback');
    reference_lines(ax,band); style_axes(ax,span);
    title(ax,{sprintf('%s | C = %.5f',model_names{m},row.Gain), ...
        sprintf('Integrated: total %.3f dB | without added magnetic noise %.3f dB | magnetic response %.3f dB', ...
        row.Feedback_dB,row.WithoutAddedMag_dB,row.AddedMagResponse_dB)},'FontWeight','normal','FontSize',11);
    xlabel(ax,'Frequency (kHz)'); ylabel(ax,'PSD / supplied coherent PSD (dB)');
    legend(ax,'Location','eastoutside','FontSize',10,'Interpreter','none');
end
savefigure(fig,out,'noise_components');

fig=newfigure('Hardware delay at fixed gain',[150 130 1400 990],visible);
tl=tiledlayout(fig,2,2,'TileSpacing','loose','Padding','compact');
title(tl,'Hardware delay with causal filtering and a fixed gain','FontSize',18,'FontWeight','bold');
subtitle(tl,'The gain is fixed to the causal, zero-added-delay optimum; electronics and filter response are unchanged','FontSize',11);
dc=lines(numel(cfg.delay_scan_us));
for m=1:2
    ax=nexttile(tl); hold(ax,'on');
    plot(ax,x,relative(result.psd_no_feedback(sel),ref(sel)),'Color',gray,'LineWidth',1.2, ...
        'LineStyle','--','DisplayName','No feedback');
    for d=1:numel(cfg.delay_scan_us)
        P=result.delay_psd{m,d};
        dr=result.delay_summary((m-1)*numel(cfg.delay_scan_us)+d,:);
        plot(ax,x,relative(P(sel),ref(sel)),'Color',dc(d,:),'LineWidth',1.4, ...
            'DisplayName',sprintf('%.2f us',dr.ActualDelay_us));
    end
    reference_lines(ax,band); style_axes(ax,span);
    title(ax,sprintf('%s | fixed C = %.5f',model_names{m},result.cases{m,2}.gain),'FontWeight','normal','FontSize',12);
    xlabel(ax,'Frequency (kHz)'); ylabel(ax,'PSD / supplied coherent PSD (dB)');
    legend(ax,'Location','northoutside','NumColumns',3,'FontSize',9,'Interpreter','none');
    ax=nexttile(tl); hold(ax,'on');
    dr=result.delay_summary((m-1)*numel(cfg.delay_scan_us)+(1:numel(cfg.delay_scan_us)),:);
    plot(ax,dr.ActualDelay_us,dr.Noise_dB,'-o','Color',colors(3,:),'LineWidth',1.6, ...
        'MarkerSize',6,'MarkerFaceColor','white');
    style_axes(ax,[]);
    title(ax,[model_names{m} ' | integrated target-band noise'],'FontWeight','normal','FontSize',12);
    xlabel(ax,'Added hardware delay (us)'); ylabel(ax,'Integrated band power / reference (dB)');
    % Tight limits expose small differences instead of implying a large delay penalty.
    yr=[min(dr.Noise_dB),max(dr.Noise_dB)]; pad=max(diff(yr)*0.2,0.001);
    ylim(ax,yr+[-pad pad]);
    if numel(unique(dr.ActualDelay_us))>1
        xlim(ax,[min(dr.ActualDelay_us),max(dr.ActualDelay_us)]);
    end
end
savefigure(fig,out,'delay_effect');
end

function fig=newfigure(name,pos,visible)
fig=figure('Name',name,'Color','white','Position',pos,'Visible',visible, ...
    'DefaultAxesFontName','Arial','DefaultAxesFontSize',11,'DefaultTextInterpreter','none');
end

function style_axes(ax,xlimits)
grid(ax,'on'); ax.GridAlpha=0.16; ax.Box='off'; ax.LineWidth=0.8;
ax.TickDir='out'; ax.Layer='top';
if ~isempty(xlimits), xlim(ax,xlimits); end
end

function reference_lines(ax,band)
yline(ax,0,'k:','0 dB: supplied coherent record','LineWidth',1.1, ...
    'HandleVisibility','off','LabelHorizontalAlignment','left','FontSize',9);
xline(ax,band(1),':','Color',[0.45 0.45 0.45],'HandleVisibility','off');
xline(ax,band(2),':','Color',[0.45 0.45 0.45],'HandleVisibility','off');
end

function name=short_scenario(s,cfg,Fs)
if s==1
    name='Zero phase, no electronics';
elseif s==2
    name='Causal, delay 0';
else
    name=sprintf('Causal, delay %.2f us',round(cfg.delay_time*Fs)/Fs*1e6);
end
end

function y=relative(P,reference)
y=todb(P./max(reference,realmin));
end

function y=todb(P)
y=10*log10(max(P,realmin));
end

function savefigure(fig,out,name)
drawnow;
exportgraphics(fig,fullfile(out,[name '.png']),'Resolution',180);
savefig(fig,fullfile(out,[name '.fig']));
end
