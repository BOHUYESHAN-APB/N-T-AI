// AudioManager.js
class AudioManager {
    constructor() {
        this.ctx = null;       // 延迟到 unlock 再建
        this.models = new Map();  // 同前
        this.priority = {LanLan1: true, LanLan2: false};         // 同前
    }

    ensureCtx() {
        if (!this.ctx) {
            this.ctx = new (window.AudioContext || window.webkitAudioContext)();
        }
        if (this.ctx.state === 'suspended') {
            this.ctx.resume();
        }
        for (const [id, m] of this.models) {
            if (!m.gain) {
                const {gain, analyser, outputGain} = this._buildNodes();
                Object.assign(m, {gain, analyser, outputGain});
            }
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
                const {gain, analyser, outputGain} = this._buildNodes();
                Object.assign(m, {gain, analyser, outputGain});
            }
        }
    }

    /** 提供给外部：注册模型 */
    register(modelId) {
        if (this.models.has(modelId)) return;

        // 先占个坑，真正的节点等 unlock 后再补
        const modelState = {
            gain: null,
            analyser: null,
            outputGain: null,
            queue: [],
            nextTime: 0,
            playingSources: new Set(),
            animationFrameId: null,
            lipSyncStopAt: 0,
        };
        this.models.set(modelId, modelState);

        // [Fix] If context is already unlocked, build nodes immediately!
        if (this.ctx && this.ctx.state !== 'closed') {
             const {gain, analyser, outputGain} = this._buildNodes();
             Object.assign(modelState, {gain, analyser, outputGain});
        }
    }

    /** 内部小工具：生成 Gain + Analyser */
    _buildNodes() {
        const gain = this.ctx.createGain(); // Input Gain (Ducking)
        const analyser = this.ctx.createAnalyser();
        const outputGain = this.ctx.createGain(); // Output Gain (Volume/Mute)
        
        gain.connect(analyser);
        analyser.connect(outputGain);
        outputGain.connect(this.ctx.destination);
        
        analyser.fftSize = 2048;
        
        // [Triple Playback Fix] Default to MUTED to prevent echo.
        // Flutter plays the audio. Live2D uses it for lip-sync only.
        outputGain.gain.value = 0.0; 
        
        return {gain, analyser, outputGain};
    }

    /** 往某个模型的播放队列塞一段 PCM buffer */
    enqueue(modelId, audioBuffer, seq) {
        const m = this.models.get(modelId);
        m.queue.push({buffer: audioBuffer, seq});
        m.queue.sort((a, b) => a.seq - b.seq);
        if (m.playingSources.size === 0) {
            m.nextTime = this.ctx.currentTime + 0.02;
            let model = null;
            if (window.live2dManager && window.live2dManager.currentModel) {
                model = window.live2dManager.currentModel;
            } else if (window[modelId] && window[modelId].live2dModel) {
                model = window[modelId].live2dModel; // Legacy fallback
            }
            if (model) {
                try { this.startLipSync(model, m.analyser, modelId); } catch (_) {}
            }
        }
        if (!m.schedulingLoop) this._scheduleLoop(modelId);
    }

    // ————— 私有 —————
    _scheduleLoop(modelId) {
        const m = this.models.get(modelId);
        m.schedulingLoop = true;
        const lookAhead = 4;               // 4 s 预调度
        const fadeTime = 0.05; // 50ms淡入淡出时间 (Increased for smoothness)
        const loop = () => {
            try {
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

                // Resolve Model Object
                let model = null;
                if (window.live2dManager && window.live2dManager.currentModel) {
                    model = window.live2dManager.currentModel;
                } else if (window[modelId] && window[modelId].live2dModel) {
                    model = window[modelId].live2dModel; // Legacy fallback
                }

                src.onended = () => {
                    m.playingSources.delete(src);
                    if (m.playingSources.size === 0) {
                        this.stopLipSync(model, modelId);
                    }
                    this._updateDuck();          // 有可能释放优先级
                    this._checkFinished(modelId);
                };

                src.start(m.nextTime);
                const clipEnd = m.nextTime + buffer.duration;
                const margin = 0.25;
                const hardStop = clipEnd + margin;
                if (!m.lipSyncStopAt || hardStop > m.lipSyncStopAt) {
                    m.lipSyncStopAt = hardStop;
                }
                m.nextTime = clipEnd;
                m.playingSources.add(src);
                if (model) {
                    this.startLipSync(model, m.analyser, modelId);
                }
                this._updateDuck();            // 让优先级立即生效
                console.log(`[AudioLoader] [${Date.now()}] Playback started. Buffer duration: ${buffer.duration.toFixed(3)}s`);
            }
            if (m.queue.length || m.playingSources.size) {
                setTimeout(loop, 25);
            } else {
                m.schedulingLoop = false;      // 暂停 loop，等下一包再启动
                console.log(`[AudioLoader] [${Date.now()}] Queue empty. Stopping loop.`);
            }
            } catch (e) {
                console.error('[AudioLoader] Schedule loop error:', e);
                // Retry instead of stopping completely
                if (m.queue.length > 0) {
                     console.log('[AudioLoader] Retrying loop in 100ms...');
                     setTimeout(loop, 100);
                } else {
                     m.schedulingLoop = false;
                }
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
    startLipSync(model, analyser, modelId) {
        // Prevent multiple lip sync loops for the same model
        const m = this.models.get(modelId);
        if (m && m.isLipSyncing) {
             console.log('[AudioLoader] LipSync already running for model:', modelId);
             return;
        }
        if (m) m.isLipSyncing = true;
        window.LIVE2D_AUDIO_PLAYING = true;
        if (window.live2dManager && typeof window.live2dManager.setSpeaking === 'function') {
            try { window.live2dManager.setSpeaking(true); } catch (_) {}
        }

        console.log('[AudioLoader] startLipSync called for model:', modelId);
        if (!model || !model.internalModel || !model.internalModel.coreModel) {
            console.error('[AudioLoader] Model or CoreModel not found for LipSync');
            if (m) m.isLipSyncing = false;
            return;
        }

        const frequencyData = new Uint8Array(analyser.frequencyBinCount);
        const timeData = new Uint8Array(analyser.fftSize);
        const sampleRate = this.ctx?.sampleRate || 44100;
        const binSize = sampleRate / analyser.fftSize;
        
        let smoothedMouthOpen = 0.0;
        let smoothedMouthForm = 0;
        const smoothingFactor = 0.35;
        const minThreshold = 0.003;

        const animate = () => {
            const m = this.models.get(modelId);
            if (!m) {
                return;
            }

            if (m.lipSyncStopAt && this.ctx && typeof this.ctx.currentTime === 'number') {
                if (this.ctx.currentTime >= m.lipSyncStopAt) {
                    this.stopLipSync(model, modelId);
                    return;
                }
            }
            const hasPendingAudio = (m.playingSources.size > 0 || m.queue.length > 0);
            if (!hasPendingAudio) {
                m.isLipSyncing = false;
                return;
            }

            analyser.getByteFrequencyData(frequencyData);
            analyser.getByteTimeDomainData(timeData);
            
            // RMS音量
                let sum = 0;
                for (let i = 0; i < timeData.length; i++) {
                    const val = (timeData[i] - 128) / 128;
                    sum += val * val;
                }
                const rms = Math.sqrt(sum / timeData.length);
                
                // Debug log for RMS and Lip Sync (throttled)
                if (Math.random() < 0.05) { // Increased to 5% for better visibility

                    console.log(`[AudioLoader] RMS: ${rms.toFixed(4)}, SmoothedMouth: ${smoothedMouthOpen.toFixed(4)}`);
                    try {
                         // Check available parameters if possible or just log attempt
                         // console.log('Setting ParamMouthOpenY to', smoothedMouthOpen);
                    } catch(e) {}
                }
                
                // 静音检测
            if (rms < minThreshold) {
                smoothedMouthOpen += (0 - smoothedMouthOpen) * 0.5;
                smoothedMouthForm += (0 - smoothedMouthForm) * 0.5;
                if (smoothedMouthOpen < 0.01) smoothedMouthOpen = 0;
                
                if (window.live2dManager && typeof window.live2dManager.setMouth === 'function') {
                    window.live2dManager.setMouth(smoothedMouthOpen);
                }
                try { model.internalModel.coreModel.setParameterValueById('ParamMouthOpenY', smoothedMouthOpen); } catch(e) {}
                try { model.internalModel.coreModel.setParameterValueById('ParamA', smoothedMouthOpen); } catch(e) {}
                
                m.animationFrameId = requestAnimationFrame(animate);
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
            let baseMouthOpen = Math.min(1, rms * 6.0);
            
            // [Adjusted] Vowel influence
            let targetMouthOpen = baseMouthOpen * (0.4 + vowelness * 0.8);
            
            // [Fix] Ensure minimum opening if there is significant sound
            if (rms > 0.005 && targetMouthOpen < 0.1) {
                targetMouthOpen = 0.1 + rms * 5.0;
            }

            if (highBand > midLowBand * 0.5) {
                targetMouthOpen = Math.max(targetMouthOpen, baseMouthOpen * 0.4);
            }
            
            // Debug log for Lip Sync logic (throttled)
            if (Math.random() < 0.05) {
                 console.log(`[AudioLoader] RMS: ${rms.toFixed(4)} -> TargetMouth: ${targetMouthOpen.toFixed(4)}`);
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

            // [Force] Ensure mouth closes if very small
            if (smoothedMouthOpen < 0.015) smoothedMouthOpen = 0;
            
            // [Fixed] Removed body sway logic to prevent twitching/conflict with idle motions
            // The previous sway logic was conflicting with the model's internal physics/idle animations.

            // 设置参数
            try {
                if (window.live2dManager) {
                    if (typeof window.live2dManager.setMouth === 'function') {
                        window.live2dManager.setMouth(smoothedMouthOpen);
                    }
                    if (typeof window.live2dManager.setMouthForm === 'function') {
                        window.live2dManager.setMouthForm(smoothedMouthForm);
                    }
                }

                // Legacy direct access (Manager override will take precedence if installed)
                if (model && model.internalModel && model.internalModel.coreModel) {
                    try { model.internalModel.coreModel.setParameterValueById('ParamMouthOpenY', smoothedMouthOpen); } catch(_) {}
                    try { model.internalModel.coreModel.setParameterValueById('ParamA', smoothedMouthOpen); } catch(_) {}
                    try { model.internalModel.coreModel.setParameterValueById('ParamMouthForm', smoothedMouthForm); } catch(_) {}
                }
            } catch (_) {}
            
            m.animationFrameId = requestAnimationFrame(animate);
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

    stopLipSync(model, modelId) {
        if (!model) return;
        const m = this.models.get(modelId);
        if (m) m.isLipSyncing = false; // [Fix] Reset lip sync flag so it can restart for next chunk
        window.LIVE2D_AUDIO_PLAYING = false;
        if (m && m.animationFrameId) {
            cancelAnimationFrame(m.animationFrameId);
        }
        if (window.live2dManager && typeof window.live2dManager.setSpeaking === 'function') {
            try { window.live2dManager.setSpeaking(false); } catch (_) {}
        }
        
        // 关闭嘴巴并重置嘴型
        try {
            if (model.internalModel && model.internalModel.coreModel) {
                if (window.live2dManager && typeof window.live2dManager.setMouth === 'function') {
                    window.live2dManager.setMouth(0);
                } else {
                    model.internalModel.coreModel.setParameterValueById('ParamMouthOpenY', 0);
                }
                model.internalModel.coreModel.setParameterValueById('ParamMouthForm', 0);
            }
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

/**
 * Handle audio blob (support MP3/WAV/etc via decodeAudioData)
 */
function handleAudioBlobFor(id, blob, seq) {
    blob.arrayBuffer().then(arrayBuffer => {
        const ctx = window.AM.ensureCtx();
        ctx.decodeAudioData(arrayBuffer).then(audioBuffer => {
            window.AM.enqueue(id, audioBuffer, seq);
        }).catch(e => {
            console.error("Error decoding audio data:", e);
             // Try to read as text to see if it's an error message
             blob.text().then(text => {
                  console.error("Content that failed to decode:", text.substring(0, 200));
             });
        });
    });
}

    /**
     * [New] Support URL playback to reduce delay.
     * Fetches audio, decodes it, and enqueues it for lip-sync.
     * Note: Output volume is controlled by _buildNodes() (currently 0.0 for lip-sync only).
     */
function playAudioUrl(url) {
        try { window.AM.unlock(); } catch (_) {}
        try { window.AM.ensureCtx(); } catch (_) {}
        let modelId = 'default_model';
        if (window.live2dManager && window.live2dManager.modelName) {
            modelId = window.live2dManager.modelName;
        }
        if (!window.AM.models.has(modelId)) {
             window.AM.register(modelId);
        }

        const startTime = Date.now();
        console.log(`[AudioLoader] [${startTime}] Start fetching audio URL: ${url}`);

        fetch(url)
            .then(response => {
                console.log(`[AudioLoader] [${Date.now()}] Download complete. Status: ${response.status}`);
                if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
                return response.arrayBuffer();
            })
            .then(arrayBuffer => {
                const downloadTime = Date.now() - startTime;
                console.log(`[AudioLoader] [${Date.now()}] ArrayBuffer received. Size: ${arrayBuffer.byteLength} bytes. Download time: ${downloadTime}ms`);
                
                try {
                    const ctx = window.AM.ensureCtx();
                    const decodeStart = Date.now();
                    ctx.decodeAudioData(arrayBuffer).then(audioBuffer => {
                        const decodeTime = Date.now() - decodeStart;
                        console.log(`[AudioLoader] [${Date.now()}] Audio decoded. Duration: ${audioBuffer.duration.toFixed(3)}s. Decode time: ${decodeTime}ms`);
                        
                        // Enqueue for playback (lip-sync)
                        window.AM.enqueue(modelId, audioBuffer, Date.now());
                        
                        // Safety check: if loop isn't running, it might be stuck
                        setTimeout(() => {
                            const m = window.AM.models.get(modelId);
                            if (m && !m.isLipSyncing && m.queue.length > 0) {
                                console.warn('[AudioLoader] LipSync slow to start (URL). Queue length:', m.queue.length);
                                if (!m.schedulingLoop) {
                                     console.log('[AudioLoader] Restarting loop manually');
                                     window.AM._scheduleLoop(modelId);
                                }
                            }
                        }, 500); // Check after 500ms
                        
                    }).catch(e => {
                        console.error("[AudioLoader] Error decoding audio data:", e);
                    });
                } catch (e) {
                     console.error("[AudioLoader] AudioContext error during decode:", e);
                }
            })
            .catch(e => console.error("[AudioLoader] Error fetching audio URL:", e));
    }

    /**
     * Play audio from Base64 string (called from Flutter via WebSocket)
     */
function playAudioBase64(base64String) {
    try {
        try { window.AM.unlock(); } catch (_) {}
        try { window.AM.ensureCtx(); } catch (_) {}
        const binaryString = window.atob(base64String);
        const len = binaryString.length;
        const bytes = new Uint8Array(len);
        for (let i = 0; i < len; i++) {
            bytes[i] = binaryString.charCodeAt(i);
        }
        
        // Dynamic Model Resolution
        let modelId = 'default_model';
        if (window.live2dManager && window.live2dManager.modelName) {
            modelId = window.live2dManager.modelName;
        }
        
        // Ensure registered
        if (!window.AM.models.has(modelId)) {
             window.AM.register(modelId);
        }

        console.log(`[Audio] Received audio for model: ${modelId}, Base64 length: ${base64String.length}`);
        handleAudioBlobFor(modelId, new Blob([bytes]), Date.now());
        
        // Monitor LipSync status
        setTimeout(() => {
            const m = window.AM.models.get(modelId);
            if (m && !m.isLipSyncing && m.queue.length > 0) {
                console.warn('[AudioLoader] LipSync slow to start. Queue length:', m.queue.length);
                // Do not re-enqueue to avoid triple playback
                if (!m.schedulingLoop) {
                     console.log('[AudioLoader] Restarting loop manually');
                     window.AM._scheduleLoop(modelId);
                }
            }
        }, 1000);
        
    } catch (e) {
        console.error("[Audio] Failed to process base64 audio:", e);
    }
}

window.AM = new AudioManager();
window.playAudioBase64 = playAudioBase64;
window.playAudioUrl = playAudioUrl;
window.addEventListener('pointerdown', unlockAudio, {passive: true});
window.addEventListener('keydown', unlockAudio, {passive: true});
