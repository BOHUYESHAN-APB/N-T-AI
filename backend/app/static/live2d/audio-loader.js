// AudioManager.js
class AudioManager {
    constructor() {
        this.ctx = null;       // 延迟到 unlock 再建
        this.models = new Map();  // 同前
        this.priority = {LanLan1: true, LanLan2: false};         // 同前
    }

    /** 确保 ctx 可用——若还没解锁就抛错，让调用方决定怎么做 */
    ensureCtx() {
        if (!this.ctx || this.ctx.state === 'suspended') {
            throw new Error('AudioContext not unlocked yet');
        }
        return this.ctx;
    }

    /** 在用户交互回调里调用一次即可 */
    unlock() {
        if (!this.ctx) {
            this.ctx = new (window.AudioContext || window.webkitAudioContext)();
        }
        if (this.ctx.state === 'suspended') {
            this.ctx.resume();
        }
        // 任何依赖 ctx 的 Graph 也可以在这里补建
        for (const [id, m] of this.models) {
            if (!m.gain) {
                const {gain, analyser} = this._buildNodes();
                Object.assign(m, {gain, analyser});
            }
        }
    }

    /** 提供给外部：注册模型 */
    register(modelId) {
        if (this.models.has(modelId)) return;

        // 先占个坑，真正的节点等 unlock 后再补
        this.models.set(modelId, {
            gain: null,
            analyser: null,
            queue: [],
            nextTime: 0,
            playingSources: new Set(),
            animationFrameId: null,
        });
    }

    /** 内部小工具：生成 Gain + Analyser */
    _buildNodes() {
        const gain = this.ctx.createGain();
        const analyser = this.ctx.createAnalyser();
        gain.connect(analyser);
        analyser.connect(this.ctx.destination);
        analyser.fftSize = 2048;
        return {gain, analyser};
    }

    /** 往某个模型的播放队列塞一段 PCM buffer */
    enqueue(modelId, audioBuffer, seq) {
        const m = this.models.get(modelId);
        m.queue.push({buffer: audioBuffer, seq});
        m.queue.sort((a, b) => a.seq - b.seq);
        if (m.playingSources.size === 0) {
            m.nextTime = this.ctx.currentTime + 0.1;
        }
        if (!m.schedulingLoop) this._scheduleLoop(modelId);
    }

    // ————— 私有 —————
    _scheduleLoop(modelId) {
        const m = this.models.get(modelId);
        m.schedulingLoop = true;
        const lookAhead = 4;               // 4 s 预调度
        const fadeTime = 0.0; // 20ms淡入淡出时间
        const loop = () => {
            const tNow = this.ctx.currentTime;

            while (m.queue.length && m.nextTime < tNow + lookAhead) {
                const {buffer} = m.queue.shift();
                const src = this.ctx.createBufferSource();
                // src.buffer = buffer;
                // src.connect(m.gain);

                // 应用淡入淡出包络
                const fadeGain = this.ctx.createGain();
                src.buffer = buffer;
                src.connect(fadeGain);
                fadeGain.connect(m.gain);
                fadeGain.gain.setValueAtTime(0, m.nextTime);
                fadeGain.gain.linearRampToValueAtTime(1, m.nextTime + fadeTime);
                fadeGain.gain.setValueAtTime(1, m.nextTime + buffer.duration - fadeTime);
                fadeGain.gain.linearRampToValueAtTime(0, m.nextTime + buffer.duration);

                // 口型
                if (window[modelId] && window[modelId].live2dModel) {
                    this.startLipSync(modelId, m.analyser); // 你已有的实现
                }

                src.onended = () => {
                    m.playingSources.delete(src);
                    if (m.playingSources.size === 0) this.stopLipSync(modelId);
                    this._updateDuck();          // 有可能释放优先级
                    this._checkFinished(modelId);
                };

                src.start(m.nextTime);
                m.nextTime += buffer.duration;
                m.playingSources.add(src);
                this._updateDuck();            // 让优先级立即生效
            }
            if (m.queue.length || m.playingSources.size) {
                setTimeout(loop, 25);
            } else {
                m.schedulingLoop = false;      // 暂停 loop，等下一包再启动
            }
        };
        loop();
    }

    /** 根据当前播放状态调节全局 Ducking */
    _updateDuck() {
        // 判断有没有高优先级模型在说话
        let priorityTalking = false;
        for (const [id, m] of this.models) {
            if (this.priority[id] && m.playingSources.size) {
                priorityTalking = true;
                break;
            }
        }
        for (const [id, m] of this.models) {
            const target = (priorityTalking && !this.priority[id]) ? 0.15 : 1;
            // 用小时间常数做平滑，不要瞬间断音
            m.gain.gain.cancelScheduledValues(this.ctx.currentTime);
            m.gain.gain.setTargetAtTime(target, this.ctx.currentTime, 0.05);
        }
    }

    _checkFinished(modelId) {
        const m = this.models.get(modelId);
        if (m.playingSources.size === 0 && m.queue.length === 0) {
          if (window.coder_socket?.readyState === WebSocket.OPEN) {
            window.coder_socket.send(JSON.stringify({
              action: 'finish_playing',
              input_type: modelId            // ← 或保留 'coder'，看后端协议
            }));
          }
        }
      }

    // 增强口型同步 - 支持中英文嘴型匹配
    startLipSync(modelId, analyser) {
        const model = window[modelId].live2dModel;
        const frequencyData = new Uint8Array(analyser.frequencyBinCount);
        const timeData = new Uint8Array(analyser.fftSize);
        const sampleRate = this.ctx?.sampleRate || 44100;
        const binSize = sampleRate / analyser.fftSize;
        
        // 平滑参数
        let smoothedMouthOpen = 0;
        let smoothedMouthForm = 0;
        const smoothingFactor = 0.3;
        const minThreshold = 0.02;

        const animate = () => {
            analyser.getByteFrequencyData(frequencyData);
            analyser.getByteTimeDomainData(timeData);
            
            // RMS音量
            let sum = 0;
            for (let i = 0; i < timeData.length; i++) {
                const val = (timeData[i] - 128) / 128;
                sum += val * val;
            }
            const rms = Math.sqrt(sum / timeData.length);
            
            // 静音检测
            if (rms < minThreshold) {
                smoothedMouthOpen = smoothedMouthOpen * 0.85;
                if (smoothedMouthOpen < 0.01) smoothedMouthOpen = 0;
                model.internalModel.coreModel.setParameterValueById('ParamMouthOpenY', smoothedMouthOpen);
                this.models.get(modelId).animationFrameId = requestAnimationFrame(animate);
                return;
            }
            
            // 频段能量分析
            const lowBand = this._getBandEnergy(frequencyData, 100, 500, binSize);
            const midLowBand = this._getBandEnergy(frequencyData, 500, 1500, binSize);
            const midHighBand = this._getBandEnergy(frequencyData, 1500, 3500, binSize);
            const highBand = this._getBandEnergy(frequencyData, 3500, 8000, binSize);
            
            // 元音特征
            const vowelness = (lowBand + midLowBand) / (lowBand + midLowBand + midHighBand + highBand + 0.001);
            
            // 开口度
            let baseMouthOpen = Math.min(1, rms * 6);
            let targetMouthOpen = baseMouthOpen * (0.5 + vowelness * 0.7);
            if (highBand > midLowBand * 0.5) {
                targetMouthOpen = Math.max(targetMouthOpen, baseMouthOpen * 0.4);
            }
            
            // 嘴型形状
            let targetMouthForm = 0;
            if (midLowBand > 0.1) {
                const formantRatio = midHighBand / (midLowBand + 0.001);
                targetMouthForm = Math.min(1, Math.max(-1, (formantRatio - 1) * 0.5));
            }
            
            // 平滑过渡
            smoothedMouthOpen += (targetMouthOpen - smoothedMouthOpen) * smoothingFactor;
            smoothedMouthForm += (targetMouthForm - smoothedMouthForm) * smoothingFactor * 0.5;
            
            smoothedMouthOpen = Math.min(1, Math.max(0, smoothedMouthOpen));
            smoothedMouthForm = Math.min(1, Math.max(-1, smoothedMouthForm));
            
            // 设置参数
            model.internalModel.coreModel.setParameterValueById('ParamMouthOpenY', smoothedMouthOpen);
            try {
                model.internalModel.coreModel.setParameterValueById('ParamMouthForm', smoothedMouthForm);
            } catch (_) {}
            
            this.models.get(modelId).animationFrameId = requestAnimationFrame(animate);
        }

        animate();
    }
    
    // 辅助函数：获取频段能量
    _getBandEnergy(frequencyData, minFreq, maxFreq, binSize) {
        const minBin = Math.floor(minFreq / binSize);
        const maxBin = Math.min(Math.floor(maxFreq / binSize), frequencyData.length - 1);
        if (minBin >= maxBin) return 0;
        let sum = 0, count = 0;
        for (let i = minBin; i <= maxBin; i++) {
            sum += frequencyData[i] / 255;
            count++;
        }
        return count > 0 ? sum / count : 0;
    }

    stopLipSync(modelId) {
        const model = window[modelId].live2dModel;
        cancelAnimationFrame(this.models.get(modelId).animationFrameId);
        // 关闭嘴巴并重置嘴型
        model.internalModel.coreModel.setParameterValueById('ParamMouthOpenY', 0);
        try {
            model.internalModel.coreModel.setParameterValueById('ParamMouthForm', 0);
        } catch (_) {}
    }
}

function unlockAudio() {
    try {
        window.AM.unlock();
        window.removeEventListener('pointerdown', unlockAudio);
        window.removeEventListener('keydown', unlockAudio);
        console.log('AudioContext unlocked ✔');
    } catch (e) {
        // ignore
    }
}

function handleAudioBlobFor(id, blob, seq) {
    blob.arrayBuffer().then(pcm => {
        const int16 = new Int16Array(pcm);
        const float32 = Float32Array.from(int16, v => v / 32768);
        const sr = window.AM.ctx.sampleRate;
        const audioBuf = window.AM.ctx.createBuffer(1, float32.length, sr);
        audioBuf.copyToChannel(float32, 0);
        window.AM.enqueue(id, audioBuf, seq);
    });
}

window.AM = new AudioManager();
window.addEventListener('pointerdown', unlockAudio, {passive: true});
window.addEventListener('keydown', unlockAudio, {passive: true});