window.PIXI = PIXI;

// Ensure PIXI.live2d exists
if (!PIXI.live2d) {
    console.error("PIXI.live2d is undefined. Make sure pixi-live2d-display is loaded correctly.");
    // Fallback or error handling
}

// const Live2DModel = PIXI.live2d ? PIXI.live2d.Live2DModel : undefined;

// if (!Live2DModel) {
//    console.error("Live2DModel is undefined. Check pixi-live2d-display version compatibility.");
// }

// 全局变量
let currentModel = null;
let emotionMapping = null;
let currentEmotion = 'neutral';
let pixi_app = null;
let isInitialized = false;

let motionTimer = null; // 动作持续时间定时器
let isEmotionChanging = false; // 防止快速连续点击的标志

// Live2D 管理器类
class Live2DManager {
    constructor() {
        this.currentModel = null;
        this.emotionMapping = null; // { motions: {emotion: [string]}, expressions: {emotion: [string]} }
        this.fileReferences = null; // 保存原始 FileReferences（含 Motions/Expressions）
        this.currentEmotion = 'neutral';
        this.pixi_app = null;
        this.isInitialized = false;
        this.motionTimer = null;
        this.isEmotionChanging = false;
        this.dragEnabled = false;
        this.isFocusing = false;
        this.isLocked = false;
        this.mouseTrackingEnabled = false; // 默认关闭眼神跟随 (Default: false)
        this.onModelLoaded = null;
        this.onStatusUpdate = null;
        this.idleMotionTimer = null; // 待机随机动作定时器
        this.isIdleMotionPlaying = false; // 防止待机动作重叠
        this.modelName = null; // 记录当前模型目录名
        this.modelRootPath = null; // 记录当前模型根路径，如 /static/<modelName>
        
        // 常驻表情：使用官方 expression 播放并在清理后自动重放
        this.persistentExpressionNames = [];

        // UI/Ticker 资源句柄（便于在切换模型时清理）
        this._lockIconTicker = null;
        this._lockIconElement = null;
        
        // 浮动按钮系统
        this._floatingButtonsTicker = null;
        this._floatingButtonsContainer = null;
        this._floatingButtons = {}; // 存储所有按钮元素
        this._popupTimers = {}; // 存储弹出框的定时器
        this._goodbyeClicked = false; // 标记是否点击了"请她离开"

        // 口型同步控制
        this.mouthValue = 0; // 0~1
        this.mouthParameterId = null; // 例如 'ParamMouthOpenY' 或 'ParamO'
        this._mouthOverrideInstalled = false;
        this._origUpdateParameters = null;
        this._origExpressionUpdateParameters = null;
        this._mouthTicker = null;
        this.isSpeaking = false;

        // [Parameter Override System]
        this.parameterOverrides = {}; // Stores active overrides: { "ParamName": value }
        
        // [Sway & Eye System]
        this.audioSwayParams = {}; // Stores sway offsets: { "ParamAngleX": offset }
        this.eyeParams = {}; // Stores eye offsets/targets
        this.eyeTimer = null; // Timer for random eye movements
        this.neuroBehaviorTimer = null; // Timer for neuro behavior loop
        this.isSwayEnabled = true;

        // Listen for lock toggle from Flutter
        window.addEventListener('live2d-lock-click', () => {
            this.isLocked = !this.isLocked;
            console.log('[Live2D] Lock toggled via Flutter:', this.isLocked);
        });
    }

    setSwayParams(params) {
        this.audioSwayParams = params;
    }

    // [Eye Movement System]
    startRandomEyes() {
        if (this.eyeTimer) return;
        console.log('[Live2D] Starting Random Eye Movements (Neuro-style)');
        
        const moveEyes = () => {
            if (!this.currentModel) {
                 this.eyeTimer = setTimeout(moveEyes, 1000);
                 return;
            }

            // Neuro-style: Random quick glances (saccades)
            // Range: -1 to 1
            const targetX = (Math.random() - 0.5) * 1.5; // Slight bias to center
            const targetY = (Math.random() - 0.5) * 0.5; // Less vertical movement
            
            // Duration of the glance
            const duration = 200 + Math.random() * 300; 
            
            // Perform the movement using a simple tween simulation
            const startX = this.eyeParams['ParamEyeBallX'] || 0;
            const startY = this.eyeParams['ParamEyeBallY'] || 0;
            const startTime = Date.now();
            
            const animate = () => {
                const now = Date.now();
                const progress = Math.min(1, (now - startTime) / duration);
                // EaseOutQuad
                const ease = 1 - (1 - progress) * (1 - progress);
                
                this.eyeParams['ParamEyeBallX'] = startX + (targetX - startX) * ease;
                this.eyeParams['ParamEyeBallY'] = startY + (targetY - startY) * ease;
                
                if (progress < 1) {
                    requestAnimationFrame(animate);
                }
            };
            animate();

            // Next movement in random time (0.5s to 4s)
            const nextDelay = 500 + Math.random() * 3500;
            this.eyeTimer = setTimeout(moveEyes, nextDelay);
        };
        
        moveEyes();
    }

    stopRandomEyes() {
        if (this.eyeTimer) {
            clearTimeout(this.eyeTimer);
            this.eyeTimer = null;
        }
        this.eyeParams = {};
    }

    // [Neuro Behavior System]
    startNeuroBehavior() {
        if (this.neuroBehaviorTimer) return;
        console.log('[Live2D] Starting Neuro Behavior System');

        const behaviorLoop = () => {
            if (!this.currentModel) {
                this.neuroBehaviorTimer = setTimeout(behaviorLoop, 2000);
                return;
            }

            // Only trigger if not already playing a motion (to avoid conflict)
            // But we want to allow overlay on idle.
            // Check if user is manually triggering emotion?
            if (this.isEmotionChanging) {
                 this.neuroBehaviorTimer = setTimeout(behaviorLoop, 2000);
                 return;
            }

            // Random interval: 5s to 15s
            const nextDelay = 5000 + Math.random() * 10000;
            
            // Random chance to do something
            if (Math.random() < 0.4) {
                const actions = ['Wink', 'CuteWink', 'HeadTilt', 'Search', 'EyeTwitch', 'MicroBodySway', 'Giggle'];
                // If speaking, prefer subtle ones
                let candidates = actions;
                if (this.isSpeaking) {
                    candidates = ['EyeTwitch', 'MicroBodySway', 'HeadTilt'];
                }

                const action = this.getRandomElement(candidates);
                console.log(`[Neuro Behavior] Triggering: ${action}`);
                this.playMotion(action);
            }

            this.neuroBehaviorTimer = setTimeout(behaviorLoop, nextDelay);
        };

        behaviorLoop();
    }

    stopNeuroBehavior() {
        if (this.neuroBehaviorTimer) {
            clearTimeout(this.neuroBehaviorTimer);
            this.neuroBehaviorTimer = null;
        }
    }

    // 从 FileReferences 推导 EmotionMapping（用于兼容历史数据）
    deriveEmotionMappingFromFileRefs(fileRefs) {
        const result = { motions: {}, expressions: {} };

        try {
            // 推导 motions
            const motions = (fileRefs && fileRefs.Motions) || {};
            Object.keys(motions).forEach(group => {
                const items = motions[group] || [];
                const files = items
                    .map(item => (item && item.File) ? String(item.File) : null)
                    .filter(Boolean);
                result.motions[group] = files;
            });

            // 推导 expressions（按 Name 前缀分组）
            const expressions = (fileRefs && Array.isArray(fileRefs.Expressions)) ? fileRefs.Expressions : [];
            expressions.forEach(item => {
                if (!item || typeof item !== 'object') return;
                const name = String(item.Name || '');
                const file = String(item.File || '');
                if (!file) return;
                const group = name.includes('_') ? name.split('_', 1)[0] : 'neutral';
                if (!result.expressions[group]) result.expressions[group] = [];
                result.expressions[group].push(file);
            });
        } catch (e) {
            console.warn('从 FileReferences 推导 EmotionMapping 失败:', e);
        }

        return result;
    }

    // 初始化 PIXI 应用
    async initPIXI(canvasId, containerId, options = {}) {
        if (this.isInitialized) {
            console.warn('Live2D 管理器已经初始化');
            return this.pixi_app;
        }

        const defaultOptions = {
            autoStart: true,
            transparent: true,
            backgroundAlpha: 0
        };

        this.pixi_app = new PIXI.Application({
            view: document.getElementById(canvasId),
            resizeTo: document.getElementById(containerId),
            ...defaultOptions,
            ...options
        });

        // [Updated] Removed old external ticker for parameter overrides.
            // We now use installCoreOverride() which hooks into the model's internal update loop.
            // This prevents "this._applyParameterOverrides is not a function" errors and provides better motion stacking.
            console.log('[Live2D] PIXI Initialized. Ticker started:', this.pixi_app.ticker.started);

            // Auto-start autonomous behaviors
            this.startRandomEyes();
            this.startNeuroBehavior();

            this.isInitialized = true;
            return this.pixi_app;
        }

    // [Parameter Override System] Apply overrides every frame - IMPROVED VERSION
    // Combined "Smart Overlay" (Motion Stacking) and "Core Override" (Force Override)
    installCoreOverride() {
        if (!this.currentModel || !this.currentModel.internalModel) return;

        const internalModel = this.currentModel.internalModel;
        const coreModel = internalModel.coreModel;
        const motionManager = internalModel.motionManager;

        if (!coreModel) return;

        // Prevent double installation
        if (this._coreOverrideInstalled) return;

        console.log('[Live2D] Installing Core Override System for Motion Stacking');
        
        // Helper to safely get parameter index (supports Cubism 2 and 4)
        const getParamIndex = (id) => {
             let idx = -1;
             if (typeof coreModel.getParameterIndex === 'function') {
                 idx = coreModel.getParameterIndex(id);
             }
             if (idx < 0 && coreModel._parameterIds && Array.isArray(coreModel._parameterIds)) {
                 idx = coreModel._parameterIds.indexOf(id);
             }
             return idx;
        };

        // Helper to get parameter value (supports Cubism 2 and 4)
        const getParamValue = (idx) => {
             if (typeof coreModel.getParameterValueByIndex === 'function') {
                 return coreModel.getParameterValueByIndex(idx);
             } else if (typeof coreModel.getParamFloat === 'function') {
                 return coreModel.getParamFloat(idx);
             }
             return 0;
        };

        // Helper to set parameter value (supports Cubism 2 and 4)
        const setParamValue = (idx, value) => {
             if (typeof coreModel.setParameterValueByIndex === 'function') {
                 coreModel.setParameterValueByIndex(idx, value);
             } else if (typeof coreModel.setParamFloat === 'function') {
                 coreModel.setParamFloat(idx, value);
             }
        };

        // [DEBUG] Dump all available parameters to help identify the correct mouth parameter
        const dumpAllParameters = () => {
             const msg = '[Live2D DEBUG] Dumping all available parameters:';
             console.log(msg);
             if (window.logToScreen) window.logToScreen(msg);

             const paramCount = coreModel.getParameterCount ? coreModel.getParameterCount() : 
                                (coreModel._parameterCount || (coreModel._parameterIds ? coreModel._parameterIds.length : 0));
             
             if (coreModel._parameterIds) {
                 console.log('[Live2D DEBUG] _parameterIds:', coreModel._parameterIds);
             }

             let mouthParamsFound = [];
             for (let i = 0; i < paramCount; i++) {
                 let id = null;
                 if (coreModel.getParameterId) {
                     id = coreModel.getParameterId(i);
                 } else if (coreModel._parameterIds) {
                     id = coreModel._parameterIds[i];
                 }
                 
                 // If we found an ID, check if it looks like a mouth param
                 if (id) {
                     if (id.toLowerCase().includes('mouth') || id.toLowerCase().includes('open')) {
                         const info = `[Live2D DEBUG] Potential Mouth Param [${i}]: ${id}`;
                         console.log(info);
                         if (window.logToScreen) window.logToScreen(info);
                         mouthParamsFound.push(id);
                     }
                 }
             }
             if (mouthParamsFound.length === 0) {
                 if (window.logToScreen) window.logToScreen('[Live2D DEBUG] NO MOUTH PARAMS FOUND!', 'error');
             }
        };
        try { dumpAllParameters(); } catch (e) { console.error('[Live2D DEBUG] Failed to dump params:', e); }

        // Cache indices
        const mouthIds = [
            'ParamMouthOpenY', 'ParamMouthOpen', 'ParamA', 'ParamI', 'ParamU', 'ParamE', 'ParamO', 
            'PARAM_MOUTH_OPEN_Y', 'PARAM_MOUTH_OPEN', 'PARAM_A', 'PARAM_I', 'PARAM_U', 'PARAM_E', 'PARAM_O',
            'ParamMouthForm', 'PARAM_MOUTH_FORM'
        ];
        this._mouthIndices = {}; // Store on instance for debugging/updates

        const findMouthIndices = () => {
             this._mouthIndices = {};
             mouthIds.forEach(id => {
                 try {
                     const idx = getParamIndex(id);
                     if (idx >= 0) {
                         this._mouthIndices[id] = idx;
                         console.log(`[Live2D] Found mouth param: ${id} -> ${idx}`);
                     }
                 } catch (_) {}
            });
        };
        
        findMouthIndices();

        if (Object.keys(this._mouthIndices).length === 0) {
            console.warn('[Live2D] No mouth parameters found in CoreModel initially. Will retry in update loop.');
        }

        // 1. Capture original update methods
        const origMotionManagerUpdate = motionManager.update ? motionManager.update.bind(motionManager) : null;
        const origCoreModelUpdate = coreModel.update ? coreModel.update.bind(coreModel) : null;

        // 2. Override MotionManager.update (The "Smart Overlay" Layer)
        // This runs AFTER motion has applied its values, but BEFORE physics/pose.
        if (motionManager) {
            motionManager.update = (...args) => {
                try {
                    if (!this.currentModel || !this.currentModel.internalModel) return;

                    // A. Capture pre-update parameters
                    const preUpdateParams = {};
                    // Capture audio sway params
                    if (this.audioSwayParams) {
                        for (const key in this.audioSwayParams) {
                            try {
                                const idx = getParamIndex(key);
                                if (idx >= 0) preUpdateParams[key] = coreModel.getParameterValueByIndex(idx);
                            } catch (_) {}
                        }
                    }
                    // Capture general overrides
                    if (this.parameterOverrides) {
                         for (const key in this.parameterOverrides) {
                            // Skip mouth/visibility
                            if (mouthIds.includes(key) || key === 'ParamOpacity' || key === 'ParamVisibility') continue;
                            try {
                                const idx = getParamIndex(key);
                                if (idx >= 0) {
                                    // Only capture if not already captured
                                    if (preUpdateParams[key] === undefined) {
                                        preUpdateParams[key] = getParamValue(idx);
                                    }
                                }
                            } catch (_) {}
                        }
                    }

                    // B. Run original motion update
                    if (origMotionManagerUpdate) {
                        try { origMotionManagerUpdate(...args); } catch (e) {}
                    }

                    // [Force Lip Sync] Immediately after motion update
                    if (window.LanLan1 && typeof window.LanLan1.getMouth === 'function') {
                        const currentMouth = window.LanLan1.getMouth();
                        if (currentMouth > 0.01) {
                             const mouthParams = [
                                 'ParamMouthOpenY', 'ParamMouthOpen', 
                                 'PARAM_MOUTH_OPEN_Y', 'PARAM_MOUTH_OPEN',
                                 'ParamMouthA', 'ParamMouthI', 'ParamMouthU',
                                 'ParamA', 'ParamI', 'ParamU', 'ParamE', 'ParamO',
                                 'PARAM_A', 'PARAM_I', 'PARAM_U', 'PARAM_E', 'PARAM_O'
                             ];
                             mouthParams.forEach(id => {
                                 const idx = getParamIndex(id);
                                 if (idx >= 0) {
                                     setParamValue(idx, currentMouth);
                                     // Double tap with ID if possible
                                     if (coreModel.setParameterValueById) {
                                         try { coreModel.setParameterValueById(id, currentMouth); } catch(e) {}
                                     }
                                 }
                             });
                        }
                    }

                    // C. Apply Smart Overlay (Stacking)
                    
                    // 1. Apply Audio Sway Stacking (Additive Mode)
                    if (this.audioSwayParams && this.isSwayEnabled) {
                        for (const [key, value] of Object.entries(this.audioSwayParams)) {
                            try {
                                const idx = getParamIndex(key);
                                if (idx >= 0) {
                                    const currentVal = getParamValue(idx);
                                    // Add sway offset to current value (Idle Motion + Sway)
                                    // 'value' is already calculated as the offset (e.g. sin(t)*amp)
                                    setParamValue(idx, currentVal + value);
                                }
                            } catch (_) {}
                        }
                    }

                    // 2. Apply Random Eye Movements (Additive/Override)
                    if (this.eyeParams) {
                         for (const [key, value] of Object.entries(this.eyeParams)) {
                             try {
                                 const idx = getParamIndex(key);
                                 if (idx >= 0) {
                                     // For eyes, we usually override idle motion's random looking, 
                                     // or we can add to it. Let's try override first as Neuro-sama's eyes are distinct.
                                     // Actually, adding might be safer to keep blink logic working?
                                     // Blinks use ParamEyeLOpen, Looking uses ParamEyeBallX/Y.
                                     // Idle motion might move EyeBall. Let's ADD for subtle movement, or OVERRIDE for strong.
                                     // Let's use Lerp towards target to be safe?
                                     // For now: OVERRIDE because we want control.
                                     setParamValue(idx, value);
                                 }
                             } catch (_) {}
                         }
                    }

                    // 3. Apply Parameter Overrides Stacking (Smart Overlay)
                    if (this.parameterOverrides) {
                        for (const [key, value] of Object.entries(this.parameterOverrides)) {
                            if (mouthIds.includes(key) || key === 'ParamOpacity' || key === 'ParamVisibility') continue;
                            if (value === null) continue;

                            try {
                                const idx = getParamIndex(key);
                                if (idx >= 0) {
                                    const currentVal = getParamValue(idx);
                                    const preVal = preUpdateParams[key] !== undefined ? preUpdateParams[key] : currentVal;
                                    
                                    let defaultVal = 0;
                                    try {
                                        if (typeof coreModel.getParameterDefaultValueByIndex === 'function') {
                                            defaultVal = coreModel.getParameterDefaultValueByIndex(idx);
                                        }
                                    } catch(_) {}

                                    const offset = value - defaultVal; // Calculate desired offset from default

                                    // If motion changed the value, we add our offset (stacking)
                                    if (Math.abs(currentVal - preVal) > 0.001) {
                                        setParamValue(idx, currentVal + offset);
                                    } else {
                                        // Motion didn't touch it, enforce our value
                                        setParamValue(idx, value);
                                    }
                                }
                            } catch (_) {}
                        }
                    }
                } catch (err) {
                    console.error('[Live2D] Error in MotionManager.update override:', err);
                    // Fallback: try to run original update at least
                    if (origMotionManagerUpdate) {
                        try { origMotionManagerUpdate(...args); } catch (e) {}
                    }
                }
            };
        }

        // 3. Override CoreModel.update (The "Force Override" Layer)
        // This runs LAST, just before rendering. Good for Lip Sync.
        coreModel.update = () => {
            // Helper to apply mouth parameters
            const applyMouth = () => {
                if (this.mouthValue > 0 || this.mouthOverrideActive) {
                    // Retry finding indices if empty (lazy loading support)
                    if (!this._mouthIndices || Object.keys(this._mouthIndices).length === 0) {
                         findMouthIndices();
                    }

                    // Throttled debug log
                    if (Math.random() < 0.005) {
                         console.log(`[Live2D] Core Update: Forcing mouth to ${this.mouthValue}`);
                    }
                    for (const [id, idx] of Object.entries(this._mouthIndices)) {
                         let targetVal = this.mouthValue;
                         if (id === 'ParamMouthForm') {
                             if (this.mouthFormValue !== undefined) {
                                 targetVal = this.mouthFormValue;
                             } else {
                                 continue;
                             }
                         }
                         
                         try { 
                             if (typeof coreModel.setParameterValueByIndex === 'function') {
                                 coreModel.setParameterValueByIndex(idx, targetVal); 
                             } else if (typeof coreModel.setParamFloat === 'function') {
                                 coreModel.setParamFloat(idx, targetVal);
                             }
                         } catch (_) {}
                    }
                }
            };

            try {
                // A. Force Lip Sync (Priority 1) - BEFORE original update
                applyMouth();
            } catch (e) {
                console.error('[Live2D] Error in CoreModel.update override (Pre-LipSync):', e);
            }

            // B. Run original update (Computes physics/vertices based on params)
            if (origCoreModelUpdate) {
                try { origCoreModelUpdate(); } catch (e) { console.error(e); }
            } else {
                // console.warn('[Live2D] Original CoreModel.update missing!');
            }
            
            // C. POST-UPDATE Force Lip Sync (Priority 2) - AFTER original update
            // This ensures our value sticks even if physics/motion update reset it.
            try {
                applyMouth();
            } catch (e) {
                console.error('[Live2D] Error in CoreModel.update override (Post-LipSync):', e);
            }
        };

        this._coreOverrideInstalled = true;
    }

    pauseIdle(pause) {
        if (pause) this.stopIdleMotionScheduler(); else this.startIdleMotionScheduler();
    }

    setSpeaking(flag) {
        this.isSpeaking = !!flag;
        if (this.isSpeaking) this.stopIdleMotionScheduler(); else this.startIdleMotionScheduler();
    }

    // Set Audio Sway Parameters (for stacking)
    setSwayParams(params) {
        this.audioSwayParams = params; // { ParamAngleX: 0.5, ... }
    }

    // Set Mouth Value (0-1)
    setMouth(value) {
        this.mouthValue = Math.max(0, Math.min(1, Number(value) || 0));
        this.mouthOverrideActive = true;
        if (this.mouthValue > 0.1 && Math.random() < 0.05) {
             console.log(`[Live2D] setMouth called: ${value} -> stored: ${this.mouthValue}`);
        }
    }

    // Set Mouth Form Value (-1 to 1)
    setMouthForm(value) {
        this.mouthFormValue = Math.max(-1, Math.min(1, Number(value) || 0));
        this.mouthOverrideActive = true;
    }

    // [New] Set Parameter Override (for procedural stacking)
    setParameterOverride(id, value) {
        if (!this.parameterOverrides) this.parameterOverrides = {};
        
        // Model Compatibility Check: Only set if model supports it
        if (this.currentModel && this.currentModel.internalModel && this.currentModel.internalModel.coreModel) {
            const coreModel = this.currentModel.internalModel.coreModel;
            try {
                let idx = -1;
                if (typeof coreModel.getParameterIndex === 'function') {
                    idx = coreModel.getParameterIndex(id);
                }
                if (idx < 0 && coreModel._parameterIds && Array.isArray(coreModel._parameterIds)) {
                    idx = coreModel._parameterIds.indexOf(id);
                }

                if (idx < 0) {
                    // console.warn(`Model does not support parameter: ${id}`);
                    return; // Skip unsupported parameters
                }
            } catch (e) { return; }
        }
        
        this.parameterOverrides[id] = value;
    }
    
    // [New] Clear Parameter Overrides
    clearParameterOverrides() {
        this.parameterOverrides = {};
    }


    // 加载用户偏好
    async loadUserPreferences() {
        try {
            const response = await fetch('/api/preferences');
            if (response.ok) {
                return await response.json();
            }
        } catch (error) {
            console.warn('加载用户偏好失败:', error);
        }
        return [];
    }

    // 保存用户偏好
    async saveUserPreferences(modelPath, position, scale) {
        try {
            const preferences = {
                model_path: modelPath,
                position: position,
                scale: scale
            };
            const response = await fetch('/api/preferences', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(preferences)
            });
            const result = await response.json();
            return result.success;
        } catch (error) {
            console.error("保存偏好失败:", error);
            return false;
        }
    }



    // 随机选择数组中的一个元素
    getRandomElement(array) {
        if (!array || array.length === 0) return null;
        return array[Math.floor(Math.random() * array.length)];
    }

    // 清除expression到默认状态（使用官方API）
    clearExpression() {
        // [New] Clear procedural overrides
        this.clearParameterOverrides();

        if (this.currentModel && this.currentModel.internalModel && this.currentModel.internalModel.motionManager && this.currentModel.internalModel.motionManager.expressionManager) {
            try {
                this.currentModel.internalModel.motionManager.expressionManager.stopAllExpressions();
                this.currentModel.internalModel.motionManager.expressionManager.resetExpression();
                console.log('expression已使用官方API清除到默认状态');
            } catch (resetError) {
                console.warn('使用官方API清除expression失败:', resetError);
            }
        } else {
            console.warn('无法访问expressionManager，expression清除失败');
        }

        // 如存在常驻表情，清除后立即重放常驻，保证不被清掉
        this.applyPersistentExpressionsNative();
    }

    // 程序化表情 fallback
    playProceduralExpression(emotion) {
        if (!this.currentModel || !this.currentModel.internalModel || !this.currentModel.internalModel.coreModel) return;
        
        console.log(`应用程序化表情 (Stacked): ${emotion}`);
        
        // Clear previous overrides first to avoid mixing conflicting emotions?
        // For now, let's just overwrite.
        
        const setParam = (id, value) => {
            this.setParameterOverride(id, value);
        };

        switch(emotion.toLowerCase()) {
            case 'sad':
                setParam('ParamMouthForm', -0.8);
                setParam('ParamBrowLY', -0.4);
                setParam('ParamBrowRY', -0.4);
                setParam('ParamEyeLOpen', 0.9);
                setParam('ParamEyeROpen', 0.9);
                setParam('ParamAngleZ', -2.0); // Slight tilt
                break;
            case 'happy':
            case 'smile':
                setParam('ParamMouthForm', 1.0);
                setParam('ParamCheek', 0.5);
                setParam('ParamEyeLOpen', 1.0);
                setParam('ParamEyeROpen', 1.0);
                break;
            case 'angry':
                setParam('ParamMouthForm', -0.5);
                setParam('ParamBrowLY', -0.6);
                setParam('ParamBrowRY', -0.6);
                setParam('ParamBrowLAngle', 0.5);
                setParam('ParamBrowRAngle', 0.5);
                break;
            case 'surprise':
            case 'surprised':
                setParam('ParamMouthOpenY', 0.4);
                setParam('ParamEyeLOpen', 1.2);
                setParam('ParamEyeROpen', 1.2);
                setParam('ParamBrowLY', 0.3);
                setParam('ParamBrowRY', 0.3);
                break;
            case 'shy':
            case 'shyblush':
                setParam('ParamCheek', 0.8);
                setParam('ParamMouthForm', 0.3);
                setParam('ParamEyeBallX', -0.3);
                setParam('ParamEyeBallY', -0.2);
                break;
            case 'thinking':
            case 'thinkingpose':
                setParam('ParamBrowLY', 0.2);
                setParam('ParamBrowRY', 0.2);
                setParam('ParamMouthForm', -0.2);
                // Maybe tilt head a bit?
                setParam('ParamAngleZ', 5.0); 
                break;
            default:
                // Neutral - clear overrides
                this.clearParameterOverrides();
                break;
        }
    }

    // 播放表情（优先使用 EmotionMapping.expressions）
    async playExpression(emotion) {
        if (!this.currentModel || !this.emotionMapping) {
            console.warn('无法播放表情：模型或映射配置未加载');
            return;
        }

        // EmotionMapping.expressions 规范：{ emotion: ["expressions/xxx.exp3.json", ...] }
        let expressionFiles = (this.emotionMapping.expressions && this.emotionMapping.expressions[emotion]) || [];

        // 兼容旧结构：从 FileReferences.Expressions 里按前缀分组
        if ((!expressionFiles || expressionFiles.length === 0) && this.fileReferences && Array.isArray(this.fileReferences.Expressions)) {
            const candidates = this.fileReferences.Expressions.filter(e => (e.Name || '').startsWith(emotion));
            expressionFiles = candidates.map(e => e.File).filter(Boolean);
        }

        if (!expressionFiles || expressionFiles.length === 0) {
            console.log(`未找到情感 ${emotion} 对应的表情文件，尝试程序化表情`);
            this.playProceduralExpression(emotion);
            return;
        }

        const choiceFile = this.getRandomElement(expressionFiles);
        if (!choiceFile) return;
        
        try {
            // 计算表达文件路径（相对模型根目录）
            const expressionPath = this.resolveAssetPath(choiceFile);
            const response = await fetch(expressionPath);
            if (!response.ok) {
                throw new Error(`Failed to load expression: ${response.statusText}`);
            }
            
            const expressionData = await response.json();
            console.log(`加载表情文件: ${choiceFile}`, expressionData);
            
            // 方法1: 尝试使用原生expression API
            if (this.currentModel.expression) {
                try {
                    // 在 FileReferences 中查找匹配的表情名称
                    let expressionName = null;
                    if (this.fileReferences && this.fileReferences.Expressions) {
                        for (const expr of this.fileReferences.Expressions) {
                            if (expr.File === choiceFile) {
                                expressionName = expr.Name;
                                break;
                            }
                        }
                    }
                    
                    // 如果找不到，回退到使用文件名
                    if (!expressionName) {
                        const base = String(choiceFile).split('/').pop() || '';
                        expressionName = base.replace('.exp3.json', '');
                    }
                    
                    console.log(`尝试使用原生API播放expression: ${expressionName} (file: ${choiceFile})`);
                    
                    const expression = await this.currentModel.expression(expressionName);
                    if (expression) {
                        console.log(`成功使用原生API播放expression: ${expressionName}`);
                        return; // 成功播放，直接返回
                    } else {
                        console.warn(`原生expression API未返回有效结果 (name: ${expressionName})，回退到手动参数设置`);
                    }
                } catch (error) {
                    console.warn('原生expression API出错:', error);
                }
            }
            
            // 方法2: 回退到手动参数设置
            console.log('使用手动参数设置播放expression');
            if (expressionData.Parameters) {
                for (const param of expressionData.Parameters) {
                    try {
                        this.currentModel.internalModel.coreModel.setParameterValueById(param.Id, param.Value);
                    } catch (paramError) {
                        console.warn(`设置参数 ${param.Id} 失败:`, paramError);
                    }
                }
            }
            
            console.log(`手动设置表情: ${choiceFile}`);
        } catch (error) {
            console.error('播放表情失败:', error);
        }

        // 重放常驻表情，确保不被覆盖
        try { await this.applyPersistentExpressionsNative(); } catch (e) {}
    }

    // 直接设置参数 (用于 Flutter 实时控制)
    updateParameters(params) {
        if (!this.currentModel || !this.currentModel.internalModel || !this.currentModel.internalModel.coreModel) return;
        
        const core = this.currentModel.internalModel.coreModel;
        
        // Mapping Flutter ExpressionData to Live2D Parameters (Standard Cubism)
        // params: { mouth, eyes, eyebrow, blush, pupilX, pupilY, headTilt }
        
        if (params.mouth !== undefined) {
            // Mouth Open: 0..1
            // Flutter mouth: -1..1. Map -1..0 to frown (not standard param), 0..1 to open.
            // Usually ParamMouthOpenY is 0..1.
            let openY = params.mouth > 0 ? params.mouth : 0;
            // core.setParameterValueById('ParamMouthOpenY', openY); // Let lip-sync handle this if active
            
            // Mouth Form: -1 (sad) .. 1 (smile)
            core.setParameterValueById('ParamMouthForm', params.mouth); 
        }
        
        if (params.eyes !== undefined) {
            // Eyes Open: 0..1
            core.setParameterValueById('ParamEyeLOpen', params.eyes);
            core.setParameterValueById('ParamEyeROpen', params.eyes);
        }
        
        if (params.eyebrow !== undefined) {
            // Eyebrow Y: -1..1
            core.setParameterValueById('ParamBrowLY', params.eyebrow);
            core.setParameterValueById('ParamBrowRY', params.eyebrow);
        }
        
        if (params.pupilX !== undefined) {
            core.setParameterValueById('ParamEyeBallX', params.pupilX);
        }
        
        if (params.pupilY !== undefined) {
            core.setParameterValueById('ParamEyeBallY', params.pupilY);
        }
        
        if (params.blush !== undefined) {
            core.setParameterValueById('ParamCheek', params.blush);
        }
        
        if (params.headTilt !== undefined) {
            // Head Z: -30..30 degrees usually. Flutter sends radians small value?
            // Flutter headTilt is -0.5 .. 0.5. 
            // Let's map -0.5 -> -30, 0.5 -> 30
            core.setParameterValueById('ParamAngleZ', params.headTilt * 60);
        }
    }

    // 参数插值动画 helper
    tweenParameters(targetParams, duration, easingFunc = (t) => t) {
        return new Promise((resolve, reject) => {
            // Check cancellation token
            if (this.cancelProceduralMotion) {
                reject('Cancelled');
                return;
            }

            const startParams = {};
            const keys = Object.keys(targetParams);
            
            // Capture start values
            keys.forEach(key => {
                if (this.parameterOverrides && this.parameterOverrides[key] !== undefined) {
                    startParams[key] = this.parameterOverrides[key];
                } else {
                    try {
                        startParams[key] = this.currentModel.internalModel.coreModel.getParameterValueById(key);
                    } catch (e) {
                        startParams[key] = 0;
                    }
                }
            });

            const startTime = performance.now();
            let frameId = null;

            const animate = (currentTime) => {
                // Check cancellation
                if (this.cancelProceduralMotion) {
                    cancelAnimationFrame(frameId);
                    reject('Cancelled');
                    return;
                }

                const elapsed = currentTime - startTime;
                const progress = Math.min(elapsed / duration, 1);
                const easedProgress = easingFunc(progress);

                const currentFrameParams = {};
                keys.forEach(key => {
                    const start = startParams[key];
                    const end = targetParams[key];
                    // Only interpolate if both are numbers
                    if (typeof start === 'number' && typeof end === 'number') {
                        currentFrameParams[key] = start + (end - start) * easedProgress;
                    }
                });

                this.applyParameters(currentFrameParams, true); // Silent update

                if (progress < 1) {
                    frameId = requestAnimationFrame(animate);
                } else {
                    // Ensure final state is applied exactly (handles nulls/releases)
                    this.applyParameters(targetParams, true);
                    resolve();
                }
            };
            frameId = requestAnimationFrame(animate);
        });
    }

    // 播放动作
    async playMotion(emotion) {
        if (!this.currentModel) {
            console.warn('无法播放动作：模型未加载');
            return;
        }

        // Cancel previous procedural motion & smooth release
        this.cancelProceduralMotion = true;
        await new Promise(r => setTimeout(r, 10));
        this.cancelProceduralMotion = false;
        
        // Release existing overrides to prevent frozen state
        if (this.parameterOverrides && Object.keys(this.parameterOverrides).length > 0) {
             this.releaseParametersSmoothly(Object.keys(this.parameterOverrides), 300);
        }

        const easeOutCubic = t => 1 - Math.pow(1 - t, 3);
        const easeInCubic = t => t * t * t;
        const easeInOutQuad = t => t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;

        try {
            // ========== New Micro-Motions ==========
            
            if (emotion === 'SlightSmile' || emotion === 'Smile') {
                await this.tweenParameters({
                    'ParamMouthForm': 0.5, 'ParamAngleZ': 3.0, 'ParamEyeLOpen': 0.95, 'ParamEyeROpen': 0.95
                }, 400, easeOutCubic);
                await new Promise(r => setTimeout(r, 1500));
                await this.releaseParametersSmoothly(['ParamMouthForm', 'ParamAngleZ', 'ParamEyeLOpen', 'ParamEyeROpen'], 500);
                return;
            }

            if (emotion === 'MicroBodySway') {
                await this.tweenParameters({'ParamBodyAngleZ': 1.0}, 1000, easeInOutQuad);
                await this.tweenParameters({'ParamBodyAngleZ': -1.0}, 1000, easeInOutQuad);
                await this.tweenParameters({'ParamBodyAngleZ': 0.0}, 1000, easeInOutQuad);
                await this.releaseParametersSmoothly(['ParamBodyAngleZ'], 1000);
                return;
            }

            if (emotion === 'BreathSigh' || emotion === 'Sigh') {
                await this.tweenParameters({'ParamBodyAngleY': 2.0, 'ParamAngleX': 2.0, 'ParamMouthForm': -0.3}, 800, easeOutCubic);
                await new Promise(r => setTimeout(r, 200));
                await this.tweenParameters({'ParamBodyAngleY': -2.0, 'ParamAngleX': -3.0, 'ParamMouthForm': 0.0}, 1200, easeOutCubic);
                await new Promise(r => setTimeout(r, 500));
                await this.releaseParametersSmoothly(['ParamBodyAngleY', 'ParamAngleX', 'ParamMouthForm'], 800);
                return;
            }

            if (emotion === 'EyeTwitch') {
                await this.tweenParameters({'ParamEyeLOpen': 0.0}, 50, easeOutCubic);
                await this.tweenParameters({'ParamEyeLOpen': 1.0}, 50, easeInCubic);
                await new Promise(r => setTimeout(r, 50));
                await this.tweenParameters({'ParamEyeLOpen': 0.0}, 50, easeOutCubic);
                await this.tweenParameters({'ParamEyeLOpen': 1.0}, 50, easeInCubic);
                await this.releaseParametersSmoothly(['ParamEyeLOpen'], 200);
                return;
            }

            // ========== 程序化动画库 ==========
        
        // [Wink] 歪头眨眼 + 微笑 + 脸红
        if (emotion === 'Wink') {
            console.log('[Motion] Triggering procedural Wink animation');
            const winkParams = {
                'ParamEyeLOpen': 0.0, 'ParamEyeROpen': 1.0, 'ParamAngleZ': 10.0, 'ParamMouthForm': 1.0, 'ParamCheek': 0.8
            };
            await this.tweenParameters(winkParams, 200, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 400));
            const neutralParams = {
                'ParamEyeLOpen': 1.0, 'ParamEyeROpen': 1.0, 'ParamAngleZ': 0.0, 'ParamMouthForm': 0.0, 'ParamCheek': 0.0
            };
            await this.tweenParameters(neutralParams, 200, easeInCubic);
            await this.releaseParametersSmoothly(['ParamEyeLOpen', 'ParamEyeROpen', 'ParamAngleZ', 'ParamMouthForm', 'ParamCheek'], 300);
            return;
        }

        // [CuteWink] 可爱眨眼 - 歪头 + 单眼闭 + 大笑脸 + 脸红
        if (emotion === 'CuteWink') {
            console.log('[Motion] Triggering procedural CuteWink animation');
            await this.tweenParameters({
                'ParamEyeLOpen': 0.0, 'ParamEyeROpen': 1.0, 'ParamAngleZ': 15.0, 'ParamAngleX': 8.0,
                'ParamMouthForm': 1.0, 'ParamMouthOpenY': 0.2, 'ParamCheek': 1.0, 'ParamBrowLY': 0.3, 'ParamBrowRY': 0.3
            }, 250, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 500));
            await this.tweenParameters({
                'ParamEyeLOpen': 1.0, 'ParamEyeROpen': 1.0, 'ParamAngleZ': 0.0, 'ParamAngleX': 0.0,
                'ParamMouthForm': 0.3, 'ParamMouthOpenY': 0.0, 'ParamCheek': 0.3, 'ParamBrowLY': 0.0, 'ParamBrowRY': 0.0
            }, 300, easeInCubic);
            await new Promise(resolve => setTimeout(resolve, 200));
            await this.releaseParametersSmoothly(['ParamEyeLOpen', 'ParamEyeROpen', 'ParamAngleZ', 'ParamAngleX', 'ParamMouthForm', 'ParamMouthOpenY', 'ParamCheek', 'ParamBrowLY', 'ParamBrowRY'], 300);
            return;
        }

        // [ShyBlush] 害羞脸红
        if (emotion === 'ShyBlush') {
            console.log('[Motion] Triggering procedural ShyBlush animation');
            await this.tweenParameters({
                'ParamAngleY': -12.0, 'ParamAngleZ': -8.0, 'ParamCheek': 1.0, 'ParamEyeBallX': -0.5, 'ParamEyeBallY': -0.2,
                'ParamMouthForm': 0.4, 'ParamBrowLY': -0.2, 'ParamBrowRY': -0.2
            }, 400, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 800));
            await this.tweenParameters({
                'ParamAngleY': 0.0, 'ParamAngleZ': 0.0, 'ParamCheek': 0.3, 'ParamEyeBallX': 0.0, 'ParamEyeBallY': 0.0,
                'ParamMouthForm': 0.0, 'ParamBrowLY': 0.0, 'ParamBrowRY': 0.0
            }, 400, easeInCubic);
            await this.releaseParametersSmoothly(['ParamAngleY', 'ParamAngleZ', 'ParamCheek', 'ParamEyeBallX', 'ParamEyeBallY', 'ParamMouthForm', 'ParamBrowLY', 'ParamBrowRY'], 400);
            return;
        }

        // [HeadTilt] 歪头
        if (emotion === 'HeadTilt') {
            console.log('[Motion] Triggering procedural HeadTilt animation');
            const direction = Math.random() > 0.5 ? 1 : -1;
            await this.tweenParameters({
                'ParamAngleZ': 8.0 * direction, 'ParamAngleX': 3.0 * direction,
                'ParamEyeLOpen': 1.1, 'ParamEyeROpen': 1.1, 'ParamBrowLY': 0.3, 'ParamBrowRY': 0.3
            }, 600, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 800));
            await this.tweenParameters({
                'ParamAngleZ': 0.0, 'ParamAngleX': 0.0,
                'ParamEyeLOpen': 1.0, 'ParamEyeROpen': 1.0, 'ParamBrowLY': 0.0, 'ParamBrowRY': 0.0
            }, 500, easeInCubic);
            await this.releaseParametersSmoothly(['ParamAngleZ', 'ParamAngleX', 'ParamEyeLOpen', 'ParamEyeROpen', 'ParamBrowLY', 'ParamBrowRY'], 500);
            return;
        }

        // [Giggle] 咯咯笑
        if (emotion === 'Giggle') {
            console.log('[Motion] Triggering procedural Giggle animation');
            await this.tweenParameters({
                'ParamMouthForm': 1.0, 'ParamMouthOpenY': 0.3, 'ParamCheek': 0.7, 'ParamEyeLOpen': 0.8, 'ParamEyeROpen': 0.8
            }, 200, easeOutCubic);
            for (let i = 0; i < 3; i++) {
                await this.tweenParameters({'ParamAngleZ': 5.0, 'ParamAngleY': 3.0}, 100, easeInOutQuad);
                await this.tweenParameters({'ParamAngleZ': -5.0, 'ParamAngleY': -3.0}, 100, easeInOutQuad);
            }
            await this.tweenParameters({
                'ParamAngleZ': 0.0, 'ParamAngleY': 0.0, 'ParamMouthForm': 0.3, 'ParamMouthOpenY': 0.0, 'ParamCheek': 0.2, 'ParamEyeLOpen': 1.0, 'ParamEyeROpen': 1.0
            }, 300, easeInCubic);
            await this.releaseParametersSmoothly(['ParamAngleZ', 'ParamAngleY', 'ParamMouthForm', 'ParamMouthOpenY', 'ParamCheek', 'ParamEyeLOpen', 'ParamEyeROpen'], 300);
            return;
        }

        // [Curious] 好奇
        if (emotion === 'Curious') {
            console.log('[Motion] Triggering procedural Curious animation');
            await this.tweenParameters({
                'ParamAngleZ': 10.0, 'ParamAngleY': 5.0, 'ParamEyeLOpen': 1.2, 'ParamEyeROpen': 1.2,
                'ParamBrowLY': 0.5, 'ParamBrowRY': 0.5, 'ParamEyeBallY': 0.2
            }, 300, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 700));
            await this.tweenParameters({
                'ParamAngleZ': 0.0, 'ParamAngleY': 0.0, 'ParamEyeLOpen': 1.0, 'ParamEyeROpen': 1.0,
                'ParamBrowLY': 0.0, 'ParamBrowRY': 0.0, 'ParamEyeBallY': 0.0
            }, 300, easeInCubic);
            await this.releaseParametersSmoothly(['ParamAngleZ', 'ParamAngleY', 'ParamEyeLOpen', 'ParamEyeROpen', 'ParamBrowLY', 'ParamBrowRY', 'ParamEyeBallY'], 300);
            return;
        }

        // [Nod] 点头
        if (emotion === 'Nod') {
            console.log('[Motion] Triggering procedural Nod animation');
            for (let i = 0; i < 2; i++) {
                await this.tweenParameters({'ParamAngleY': -8.0}, 500, easeOutCubic);
                await this.tweenParameters({'ParamAngleY': 4.0}, 500, easeInCubic);
            }
            await this.tweenParameters({'ParamAngleY': 0.0}, 300, easeInCubic);
            await this.releaseParametersSmoothly(['ParamAngleY'], 300);
            return;
        }

        // [HeadShake] 摇头
        if (emotion === 'HeadShake') {
            console.log('[Motion] Triggering procedural HeadShake animation');
            for (let i = 0; i < 2; i++) {
                await this.tweenParameters({'ParamAngleX': 10.0}, 600, easeOutCubic);
                await this.tweenParameters({'ParamAngleX': -10.0}, 600, easeInCubic);
            }
            await this.tweenParameters({'ParamAngleX': 0.0}, 300, easeInCubic);
            await this.releaseParametersSmoothly(['ParamAngleX'], 300);
            return;
        }

        // [Search] 左看看右看看
        if (emotion === 'Search' || emotion === 'LookAround') {
            console.log('[Motion] Triggering procedural Search/LookAround animation');
            await this.tweenParameters({'ParamAngleX': -15.0, 'ParamEyeBallX': -0.8, 'ParamAngleZ': -3.0}, 1200, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 800));
            await this.tweenParameters({'ParamAngleX': 15.0, 'ParamEyeBallX': 0.8, 'ParamAngleZ': 3.0}, 2000, easeInOutQuad);
            await new Promise(resolve => setTimeout(resolve, 800));
            await this.tweenParameters({'ParamAngleX': 0.0, 'ParamEyeBallX': 0.0, 'ParamAngleZ': 0.0}, 1000, easeInCubic);
            await this.releaseParametersSmoothly(['ParamAngleX', 'ParamEyeBallX', 'ParamAngleZ'], 500);
            return;
        }

        // [ThinkingPose] 思考姿态
        if (emotion === 'ThinkingPose') {
            console.log('[Motion] Triggering procedural ThinkingPose animation');
            await this.tweenParameters({
                'ParamAngleY': 12.0, 'ParamAngleX': 5.0, 'ParamEyeBallY': 0.5, 'ParamEyeBallX': 0.3,
                'ParamBrowLY': 0.3, 'ParamBrowRY': 0.3, 'ParamBrowLAngle': 0.3, 'ParamBrowRAngle': 0.3
            }, 400, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 1000));
            await this.tweenParameters({
                'ParamAngleY': 0.0, 'ParamAngleX': 0.0, 'ParamEyeBallY': 0.0, 'ParamEyeBallX': 0.0,
                'ParamBrowLY': 0.0, 'ParamBrowRY': 0.0, 'ParamBrowLAngle': 0.0, 'ParamBrowRAngle': 0.0
            }, 400, easeInCubic);
            await this.releaseParametersSmoothly(['ParamAngleY', 'ParamAngleX', 'ParamEyeBallY', 'ParamEyeBallX', 'ParamBrowLY', 'ParamBrowRY', 'ParamBrowLAngle', 'ParamBrowRAngle'], 400);
            return;
        }

        // [Surprised] 惊讶
        if (emotion === 'Surprised') {
            console.log('[Motion] Triggering procedural Surprised animation');
            await this.tweenParameters({
                'ParamEyeLOpen': 1.3, 'ParamEyeROpen': 1.3, 'ParamAngleY': -8.0, 'ParamBodyAngleY': -3.0,
                'ParamMouthOpenY': 0.5, 'ParamBrowLY': 0.6, 'ParamBrowRY': 0.6
            }, 150, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 500));
            await this.tweenParameters({
                'ParamEyeLOpen': 1.0, 'ParamEyeROpen': 1.0, 'ParamAngleY': 0.0, 'ParamBodyAngleY': 0.0,
                'ParamMouthOpenY': 0.0, 'ParamBrowLY': 0.0, 'ParamBrowRY': 0.0
            }, 300, easeInCubic);
            await this.releaseParametersSmoothly(['ParamEyeLOpen', 'ParamEyeROpen', 'ParamAngleY', 'ParamBodyAngleY', 'ParamMouthOpenY', 'ParamBrowLY', 'ParamBrowRY'], 300);
            return;
        }

        // [HappyBounce] 开心跳跃
        if (emotion === 'HappyBounce') {
            console.log('[Motion] Triggering procedural HappyBounce animation');
            await this.tweenParameters({'ParamMouthForm': 1.0, 'ParamCheek': 0.5}, 150, easeOutCubic);
            for (let i = 0; i < 3; i++) {
                await this.tweenParameters({'ParamAngleY': 8.0, 'ParamBodyAngleY': 3.0}, 100, easeOutCubic);
                await this.tweenParameters({'ParamAngleY': -2.0, 'ParamBodyAngleY': -1.0}, 100, easeInCubic);
            }
            await this.tweenParameters({
                'ParamAngleY': 0.0, 'ParamBodyAngleY': 0.0, 'ParamMouthForm': 0.3, 'ParamCheek': 0.0
            }, 200, easeInCubic);
            await this.releaseParametersSmoothly(['ParamAngleY', 'ParamBodyAngleY', 'ParamMouthForm', 'ParamCheek'], 200);
            return;
        }

        // [Pout] 嘘嘴/不满
        if (emotion === 'Pout') {
            console.log('[Motion] Triggering procedural Pout animation');
            await this.tweenParameters({
                'ParamMouthForm': -0.8, 'ParamBrowLY': -0.4, 'ParamBrowRY': -0.4,
                'ParamAngleX': 15.0, 'ParamAngleZ': -5.0, 'ParamCheek': 0.3
            }, 300, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 800));
            await this.tweenParameters({
                'ParamMouthForm': 0.0, 'ParamBrowLY': 0.0, 'ParamBrowRY': 0.0,
                'ParamAngleX': 0.0, 'ParamAngleZ': 0.0, 'ParamCheek': 0.0
            }, 300, easeInCubic);
            await this.releaseParametersSmoothly(['ParamMouthForm', 'ParamBrowLY', 'ParamBrowRY', 'ParamAngleX', 'ParamAngleZ', 'ParamCheek'], 300);
            return;
        }

        // [Sway] 左右摇摆
        if (emotion === 'Sway') {
            console.log('[Motion] Triggering procedural Sway animation');
            const easeInOutQuad = t => t < .5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
            for (let i = 0; i < 2; i++) {
                await this.tweenParameters({'ParamBodyAngleZ': 2.0, 'ParamAngleZ': 1.0}, 2000, easeInOutQuad);
                await this.tweenParameters({'ParamBodyAngleZ': -2.0, 'ParamAngleZ': -1.0}, 2000, easeInOutQuad);
            }
            await this.tweenParameters({'ParamBodyAngleZ': 0.0, 'ParamAngleZ': 0.0}, 1500, easeInOutQuad);
            await this.releaseParametersSmoothly(['ParamBodyAngleZ', 'ParamAngleZ'], 1000);
            return;
        }

        // [PuffCheeks] 鼓起脸颊
        if (emotion === 'PuffCheeks') {
            console.log('[Motion] Triggering procedural PuffCheeks animation');
            await this.tweenParameters({'ParamCheek': 1.0, 'ParamMouthForm': -0.5, 'ParamMouthOpenY': 0.0, 'ParamEyeBallY': -0.3}, 400, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 2000));
            await this.tweenParameters({'ParamCheek': 0.0, 'ParamMouthForm': 0.0, 'ParamEyeBallY': 0.0}, 400, easeInCubic);
            await this.releaseParametersSmoothly(['ParamCheek', 'ParamMouthForm', 'ParamMouthOpenY', 'ParamEyeBallY'], 400);
            return;
        }

        // [Sleepy] 困倦
        if (emotion === 'Sleepy') {
            console.log('[Motion] Triggering procedural Sleepy animation');
            await this.tweenParameters({
                'ParamEyeLOpen': 0.3, 'ParamEyeROpen': 0.3, 'ParamAngleY': -8.0, 'ParamBrowLY': -0.3, 'ParamBrowRY': -0.3
            }, 600, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 500));
            await this.tweenParameters({'ParamEyeLOpen': 0.0, 'ParamEyeROpen': 0.0}, 400, easeOutCubic);
            await new Promise(resolve => setTimeout(resolve, 300));
            await this.tweenParameters({'ParamEyeLOpen': 0.4, 'ParamEyeROpen': 0.4}, 600, easeInCubic);
            await new Promise(resolve => setTimeout(resolve, 300));
            await this.tweenParameters({
                'ParamEyeLOpen': 1.0, 'ParamEyeROpen': 1.0, 'ParamAngleY': 0.0, 'ParamBrowLY': 0.0, 'ParamBrowRY': 0.0
            }, 400, easeInCubic);
            await this.releaseParametersSmoothly(['ParamEyeLOpen', 'ParamEyeROpen', 'ParamAngleY', 'ParamBrowLY', 'ParamBrowRY'], 400);
            return;
        }
        
        } catch (error) {
            if (error === 'Cancelled') return;
            console.error('播放动作失败 (Procedural):', error);
        }

        // ========== 原生 Motion 文件播放 ==========

        // 优先使用 Cubism 原生 Motion Group（FileReferences.Motions）
        let motions = null;
        if (this.fileReferences && this.fileReferences.Motions && this.fileReferences.Motions[emotion]) {
            motions = this.fileReferences.Motions[emotion]; // 形如 [{ File: "motions/xxx.motion3.json" }, ...]
        } else if (this.emotionMapping && this.emotionMapping.motions && this.emotionMapping.motions[emotion]) {
            // 兼容 EmotionMapping.motions: ["motions/xxx.motion3.json", ...]
            motions = this.emotionMapping.motions[emotion].map(f => ({ File: f }));
        }
        if (!motions || motions.length === 0) {
            console.warn(`未找到情感 ${emotion} 对应的动作，但将保持表情`);
            // 如果没有找到对应的motion，设置一个短定时器以确保expression能够显示
            // 并且不设置回调来清除效果，让表情一直持续
            this.motionTimer = setTimeout(() => {
                this.motionTimer = null;
            }, 500); // 500ms应该足够让expression稳定显示
            return;
        }
        
        const choice = this.getRandomElement(motions);
        if (!choice || !choice.File) return;
        
        try {
            // 清除之前的动作定时器
            if (this.motionTimer) {
                console.log('检测到前一个motion正在播放，正在停止...');
                
                if (this.motionTimer.type === 'animation') {
                    cancelAnimationFrame(this.motionTimer.id);
                } else if (this.motionTimer.type === 'timeout') {
                    clearTimeout(this.motionTimer.id);
                } else if (this.motionTimer.type === 'motion') {
                    // 停止motion播放
                    try {
                        if (this.motionTimer.id && this.motionTimer.id.stop) {
                            this.motionTimer.id.stop();
                        }
                    } catch (motionError) {
                        console.warn('停止motion失败:', motionError);
                    }
                } else {
                    clearTimeout(this.motionTimer);
                }
                this.motionTimer = null;
                console.log('前一个motion已停止');
            }
            
            // 尝试使用Live2D模型的原生motion播放功能
            try {
                // 构建完整的motion路径（相对模型根目录）
                const motionPath = this.resolveAssetPath(choice.File);
                console.log(`尝试播放motion: ${motionPath}`);
                
                // 方法1: 直接使用模型的motion播放功能
                if (this.currentModel.motion) {
                    try {
                        console.log(`尝试播放motion: ${choice.File}`);
                        
                        // 使用情感名称作为motion组名，这样可以确保播放正确的motion
                        console.log(`尝试使用情感组播放motion: ${emotion}`);
                        
                const motion = await this.currentModel.motion(emotion);
                        
                        if (motion) {
                    console.log(`成功开始播放motion（情感组: ${emotion}，预期文件: ${choice.File}）`);
                            
                            // 获取motion的实际持续时间
                            let motionDuration = 5000; // 默认5秒
                            
                            // 尝试从motion文件获取持续时间
                            try {
                                const response = await fetch(motionPath);
                                if (response.ok) {
                                    const motionData = await response.json();
                                    if (motionData.Meta && motionData.Meta.Duration) {
                                        motionDuration = motionData.Meta.Duration * 1000;
                                    }
                                }
                            } catch (error) {
                                console.warn('无法获取motion持续时间，使用默认值');
                            }
                            
                            console.log(`预期motion持续时间: ${motionDuration}ms`);
                            
                            // 设置定时器在motion结束后清理motion参数（但保留expression）
                            this.motionTimer = setTimeout(() => {
                            console.log(`motion播放完成（预期文件: ${choice.File}），清除motion参数但保留expression`);
                                this.motionTimer = null;
                                this.clearEmotionEffects(); // 只清除motion参数，不清除expression
                            }, motionDuration);
                            
                            return; // 成功播放，直接返回
                        } else {
                            console.warn('motion播放失败');
                        }
                    } catch (error) {
                        console.warn('模型motion方法失败:', error);
                    }
                }
                
                // 方法2: 备用方案 - 如果方法1失败，尝试其他方法
                if (!this.motionTimer) {
                    console.log('方法1失败，尝试备用方案');
                    
                    // 这里可以添加其他备用方案，但目前方法1已经工作
                    console.warn('所有motion播放方法都失败，回退到简单动作');
                    this.playSimpleMotion(emotion);
                }
                
                // 如果所有方法都失败，回退到简单动作
                console.warn(`无法播放motion: ${choice.File}，回退到简单动作`);
                this.playSimpleMotion(emotion);
                
            } catch (error) {
                console.error('motion播放过程中出错:', error);
                this.playSimpleMotion(emotion);
            }
            
        } catch (error) {
            console.error('播放动作失败:', error);
            // 回退到简单动作
            this.playSimpleMotion(emotion);
        }
    }

    // 播放简单动作（回退方案） - 使用补间动画避免跳变
    async playSimpleMotion(emotion) {
        try {
            // 定义缓动函数
            const easeOutCubic = t => 1 - Math.pow(1 - t, 3);
            const easeInCubic = t => t * t * t;
            const easeInOutQuad = t => t < .5 ? 2 * t * t : -1 + (4 - 2 * t) * t;

            switch (emotion) {
                case 'happy':
                    // 轻微点头
                    await this.tweenParameters({'ParamAngleY': 8.0}, 150, easeOutCubic);
                    setTimeout(() => {
                        this.tweenParameters({'ParamAngleY': 0.0}, 200, easeInCubic);
                        this.motionTimer = null;
                        this.clearEmotionEffects();
                    }, 1000);
                    break;
                case 'sad':
                    // 轻微低头 + 悲伤嘴角
                    await this.tweenParameters({
                        'ParamAngleY': -5.0,
                        'ParamAngleZ': -2.0,
                        'ParamMouthForm': -0.8,
                        'ParamBrowLY': -0.3,
                        'ParamBrowRY': -0.3
                    }, 400, easeOutCubic);
                    setTimeout(() => {
                        this.tweenParameters({
                            'ParamAngleY': 0.0,
                            'ParamAngleZ': 0.0
                        }, 500, easeInCubic);
                        this.motionTimer = null;
                        this.clearEmotionEffects();
                    }, 1500);
                    break;
                case 'angry':
                    // 轻微摇头
                    await this.tweenParameters({'ParamAngleX': 5.0}, 100, easeOutCubic);
                    setTimeout(() => {
                         this.tweenParameters({'ParamAngleX': -5.0}, 100, easeInOutQuad);
                    }, 150);
                    setTimeout(() => {
                        this.tweenParameters({'ParamAngleX': 0.0}, 200, easeInCubic);
                        this.motionTimer = null;
                        this.clearEmotionEffects();
                    }, 800);
                    break;
                case 'surprised':
                    // 轻微后仰
                    await this.tweenParameters({'ParamAngleY': -8.0}, 150, easeOutCubic);
                    setTimeout(() => {
                        this.tweenParameters({'ParamAngleY': 0.0}, 200, easeInCubic);
                        this.motionTimer = null;
                        this.clearEmotionEffects();
                    }, 800);
                    break;
                default:
                    // 中性状态，重置角度
                    this.tweenParameters({
                        'ParamAngleX': 0.0,
                        'ParamAngleY': 0.0
                    }, 300, easeInCubic);
                    break;
            }
            console.log(`播放简单动作(Smooth): ${emotion}`);
        } catch (paramError) {
            console.warn('设置简单动作参数失败:', paramError);
        }
    }

    // 清理当前情感效果（清除motion参数，但保留expression）
    clearEmotionEffects() {
        let hasCleared = false;
        
        console.log('开始清理motion效果（保留expression）...');
        
        // 清除动作定时器
        if (this.motionTimer) {
            console.log(`清除motion定时器，类型: ${this.motionTimer.type || 'unknown'}`);
            
            if (this.motionTimer.type === 'animation') {
                // 取消动画帧
                cancelAnimationFrame(this.motionTimer.id);
            } else if (this.motionTimer.type === 'timeout') {
                // 清除普通定时器
                clearTimeout(this.motionTimer.id);
            } else if (this.motionTimer.type === 'motion') {
                // 停止motion播放
                try {
                    if (this.motionTimer.id && this.motionTimer.id.stop) {
                        this.motionTimer.id.stop();
                    }
                } catch (motionError) {
                    console.warn('停止motion失败:', motionError);
                }
            } else {
                // 兼容旧的定时器格式
                clearTimeout(this.motionTimer);
            }
            this.motionTimer = null;
            hasCleared = true;
        }
        
        // 停止所有motion并重置所有参数到默认值
        if (this.currentModel && this.currentModel.internalModel && this.currentModel.internalModel.motionManager) {
            try {
                // 使用官方API停止所有motion
                if (this.currentModel.internalModel.motionManager.stopAllMotions) {
                    this.currentModel.internalModel.motionManager.stopAllMotions();
                    console.log('已停止所有motion');
                    hasCleared = true;
                }
            } catch (motionError) {
                console.warn('停止motion失败:', motionError);
            }
        }
        
        // 重置所有参数到默认值（关键步骤）
        if (this.currentModel && this.currentModel.internalModel && this.currentModel.internalModel.coreModel) {
            try {
                const coreModel = this.currentModel.internalModel.coreModel;
                const paramCount = coreModel.getParameterCount();
                
                console.log(`开始重置${paramCount}个参数到默认值...`);
                
                // 遍历所有参数，将其重置为默认值
                for (let i = 0; i < paramCount; i++) {
                    try {
                        const paramId = coreModel.getParameterId(i);
                        const defaultValue = coreModel.getParameterDefaultValueByIndex(i);
                        
                        // 跳过嘴巴相关参数（这些由口型同步控制）
                        if (['ParamMouthOpenY', 'ParamMouthOpen', 'ParamA', 'ParamI', 'ParamU', 'ParamE', 'ParamO'].includes(paramId)) {
                            continue;
                        }
                        
                        // 重置参数到默认值
                        coreModel.setParameterValueByIndex(i, defaultValue);
                    } catch (e) {
                        // 单个参数重置失败不影响其他参数
                    }
                }
                try {
                    this.currentModel.internalModel.coreModel.setParameterValueById('ParamAngleX', 0);
                    this.currentModel.internalModel.coreModel.setParameterValueById('ParamAngleY', 0);
                    this.currentModel.internalModel.coreModel.setParameterValueById('ParamAngleZ', 0);
                    console.log('已使用备用方案重置角度参数');
                } catch (e) {}
                
                console.log('所有motion参数已重置到默认值');
            } catch (paramError) {
                console.warn('重置参数失败，使用备用方案:', paramError);
                // 备用方案：至少重置角度参数
                try {
                    this.currentModel.internalModel.coreModel.setParameterValueById('ParamAngleX', 0);
                    this.currentModel.internalModel.coreModel.setParameterValueById('ParamAngleY', 0);
                    this.currentModel.internalModel.coreModel.setParameterValueById('ParamAngleZ', 0);
                    console.log('已使用备用方案重置角度参数');
                } catch (e) {}
            }
        }
        
        // 重新应用当前的expression（这样expression会覆盖需要修改的参数）
        if (this.currentEmotion && this.currentEmotion !== 'neutral') {
            try {
                console.log(`重新应用当前emotion的expression: ${this.currentEmotion}`);
                this.playExpression(this.currentEmotion);
            } catch (e) {
                console.warn('重新应用expression失败:', e);
            }
        }
        
        // 重新应用常驻表情
        try {
            this.applyPersistentExpressionsNative();
        } catch (e) {
            console.warn('重新应用常驻表情失败:', e);
        }
        
        console.log('motion效果清理完成，所有参数已重置，expression已重新应用');
    }

    // 设置情感并播放对应的表情和动作
    async setEmotion(emotion) {
        // 如果情感相同，有一定概率随机播放motion（不改变expression）
        if (this.currentEmotion === emotion) {
            // 50% 的概率随机播放motion（不清除和重播expression）
            if (Math.random() < 0.5) {
                console.log(`情感相同 (${emotion})，随机播放motion（保留当前expression）`);
                await this.playMotion(emotion);
            } else {
                console.log(`情感相同 (${emotion})，跳过播放`);
                return;
            }
        }
        
        // 防止快速连续点击
        if (this.isEmotionChanging) {
            console.log('情感切换中，忽略新的情感请求');
            return;
        }
        
        console.log(`新情感触发: ${emotion}，当前情感: ${this.currentEmotion}`);
        
        // 设置标志，防止快速连续点击
        this.isEmotionChanging = true;
        
        try {
            console.log(`开始设置新情感: ${emotion}`);
            
            // 清理之前的情感效果（包括定时器等）
            this.clearEmotionEffects();
            
            // 使用官方API清除expression到默认状态
            this.clearExpression();
            
            this.currentEmotion = emotion;
            console.log(`情感已更新为: ${emotion}`);
            
            // 暂停idle动画，防止覆盖我们的动作
            if (this.currentModel && this.currentModel.internalModel && this.currentModel.internalModel.motionManager) {
                try {
                    // 尝试停止所有正在播放的动作
                    if (this.currentModel.internalModel.motionManager.stopAllMotions) {
                        this.currentModel.internalModel.motionManager.stopAllMotions();
                        console.log('已停止idle动画');
                    }
                } catch (motionError) {
                    console.warn('停止idle动画失败:', motionError);
                }
            }
            
            // 播放表情
            await this.playExpression(emotion);
            
            // 播放动作
            await this.playMotion(emotion);
            
            console.log(`情感 ${emotion} 设置完成`);
        } catch (error) {
            console.error(`设置情感 ${emotion} 失败:`, error);
        } finally {
            // 重置标志
            this.isEmotionChanging = false;
        }
    }

    // 调试：打印模型所有参数
    logModelParameters(model) {
        try {
            if (!model || !model.internalModel || !model.internalModel.coreModel) return;
            const coreModel = model.internalModel.coreModel;
            // Cubism 4 API
            if (coreModel.getParameterCount && coreModel.getParameterIds) {
                const count = coreModel.getParameterCount();
                const ids = coreModel.getParameterIds();
                console.log('[Live2D Debug] Available Parameters:', ids);
                if (typeof logToScreen === 'function') {
                    logToScreen(`[Debug] Model has ${count} parameters.`);
                    logToScreen(`[Debug] Sample: ${ids.slice(0, 5).join(', ')}...`);
                }
            } 
            // Cubism 2 API (fallback)
            else if (coreModel.getParamCount && coreModel.getParamId) {
                 // ... implementation for Cubism 2 if needed, but we are likely on Cubism 4
            }
        } catch (e) {
            console.error('Failed to log parameters:', e);
        }
    }

    // [DEBUG] Log all available parameters
    logModelParameters(model) {
        if (!model || !model.internalModel || !model.internalModel.coreModel) return;
        
        try {
            const core = model.internalModel.coreModel;
            // Cubism 4
            if (core._parameterIds) {
                console.log('[Model Parameters] IDs:', core._parameterIds);
                return;
            }
            // Cubism 2 or other
            console.log('[Model Parameters] Core Model:', core);
        } catch (e) {
            console.warn('[Model Parameters] Failed to log:', e);
        }
    }

    // 自动发现并映射表情/动作
    autoDiscoverMappings() {
        if (!this.fileReferences) return;
        
        // 1. 映射表情 (Expressions)
        if (this.fileReferences.Expressions && Array.isArray(this.fileReferences.Expressions)) {
            const expressionMap = this.emotionMapping.expressions || {};
            
            // 关键词映射规则 (Regex -> Standard Key)
            const rules = [
                { regex: /smile|happy|joy|fun/i, key: 'Happy' },
                { regex: /sad|cry|sorrow/i, key: 'Sad' },
                { regex: /angry|rage|mad/i, key: 'Angry' },
                { regex: /surprise|shock/i, key: 'Surprise' },
                { regex: /shy|blush/i, key: 'Shy' },
                { regex: /wink/i, key: 'Wink' }
            ];

            this.fileReferences.Expressions.forEach(expr => {
                const name = expr.Name || '';
                const file = expr.File || '';
                
                // 尝试匹配规则
                for (const rule of rules) {
                    if (rule.regex.test(name) || rule.regex.test(file)) {
                        if (!expressionMap[rule.key]) expressionMap[rule.key] = [];
                        // 避免重复
                        if (!expressionMap[rule.key].includes(file)) {
                            expressionMap[rule.key].push(file);
                            console.log(`[AutoDiscover] Mapped Expression: ${name} -> ${rule.key}`);
                        }
                    }
                }
            });
            
            this.emotionMapping.expressions = expressionMap;
        }

        // 2. 映射动作 (Motions)
        if (this.fileReferences.Motions) {
            const motionMap = this.emotionMapping.motions || {};
            
            // 遍历所有 Motion Group
            Object.keys(this.fileReferences.Motions).forEach(groupName => {
                const motions = this.fileReferences.Motions[groupName];
                
                // 如果 Group Name 本身就是标准词 (e.g. "TapBody"), 也可以保留
                // 这里主要处理文件名匹配
                motions.forEach(m => {
                    const file = m.File || '';
                    // 简单规则：如果文件名包含 standard key
                    const rules = [
                        { regex: /wave|greet/i, key: 'Wave' },
                        { regex: /nod|yes/i, key: 'Nod' },
                        { regex: /shake|no/i, key: 'Shake' },
                        { regex: /idle/i, key: 'Idle' }
                    ];
                    
                    for (const rule of rules) {
                        if (rule.regex.test(file) || rule.regex.test(groupName)) {
                            if (!motionMap[rule.key]) motionMap[rule.key] = [];
                            if (!motionMap[rule.key].includes(file)) {
                                motionMap[rule.key].push(file);
                                console.log(`[AutoDiscover] Mapped Motion: ${file} -> ${rule.key}`);
                            }
                        }
                    }
                });
            });
            
            this.emotionMapping.motions = motionMap;
        }
    }

    // 停止待机动作调度器
    stopIdleMotionScheduler() {
        if (this.idleMotionTimer) {
            clearInterval(this.idleMotionTimer);
            this.idleMotionTimer = null;
            this.isIdleMotionPlaying = false;
            console.log('[Idle] Idle motion scheduler stopped');
        }
    }

    // 启动待机随机动作调度器
    startIdleMotionScheduler() {
        this.stopIdleMotionScheduler();
        
        console.log('[Idle] Starting idle motion scheduler (Low Frequency)');
        this.isIdleMotionPlaying = false;
        
        // 每 12 秒检查一次 (降低频率，避免多动)
        this.idleMotionTimer = setInterval(async () => {
            // 检查模型是否加载并初始化
            if (!this.currentModel || !this.isInitialized) return;
            
            // 仅在 neutral 或 idle 状态下播放
            // 且当前没有正在改变情感或播放其他动作
            if (this.currentEmotion !== 'neutral' && this.currentEmotion !== 'idle') return;
            if (this.isEmotionChanging) return;
            if (this.motionTimer) return; // 有动作正在播放
            if (this.isIdleMotionPlaying) return; // 正在播放待机动作
            
            // 60% 概率播放随机动作 (恢复活跃度)
            if (Math.random() < 0.6) {
                this.isIdleMotionPlaying = true;

                // 定义自然的待机动作 (移除强情绪和夸张动作)
                const idleMotions = [
                    'Sway',           // 摇摆 (已优化，幅度小)
                    'MicroBodySway',  // 微小晃动 (New)
                    'Search',         // 看看周围
                    'HeadTilt',       // 歪头
                    'Nod',            // 偶尔点头
                    'SlightSmile',    // 微笑 (New)
                    'BreathSigh',     // 叹气/深呼吸 (New)
                    'EyeTwitch',      // 眨眼 (New)
                    'Blink_Special'   // 特殊眨眼 (如果映射有)
                ];
                
                // 过滤可用动作
                const availableMotions = idleMotions.filter(m => {
                    // 程序化动作总是可用
                    if (['HeadTilt', 'Nod', 'Sway', 'Search', 'MicroBodySway', 'SlightSmile', 'BreathSigh', 'EyeTwitch'].includes(m)) return true;
                    // 检查映射中是否存在
                    return (this.emotionMapping && this.emotionMapping.motions && this.emotionMapping.motions[m] && this.emotionMapping.motions[m].length > 0);
                });
                
                if (availableMotions.length > 0) {
                    // 极低概率 (5%) 播放组合动作，或者完全移除以保持平滑
                    // 用户反馈动作过多，这里我们暂时移除 Combo，只播放单个动作
                    const randomMotion = this.getRandomElement(availableMotions);
                    console.log(`[Idle] Triggering natural idle motion: ${randomMotion}`);
                    
                    // User verification helper
                    const logMsg = `⚡ [Idle] Triggered: ${randomMotion}`;
                    console.log(`%c ${logMsg}`, 'color: #00ff00; font-weight: bold; font-size: 12px;');
                    if (typeof logToScreen === 'function') {
                        logToScreen(logMsg);
                    }
                    
                    try {
                        await this.playMotion(randomMotion);
                        // 动作结束后，强制做一次极短的平滑归位，确保不卡在奇怪姿势
                        // 这里的 tweenParameters 会自动读取当前值到目标值(0)
                        // 使用较长的时间(1s)来做一个极其平滑的收尾
                        // await this.tweenParameters({
                        //    'ParamAngleX': 0, 'ParamAngleY': 0, 'ParamAngleZ': 0,
                        //    'ParamBodyAngleX': 0, 'ParamBodyAngleY': 0, 'ParamBodyAngleZ': 0
                        // }, 1000, t => t * (2 - t)); // easeOutQuad
                    } catch (e) {
                        console.warn('[Idle] Motion failed:', e);
                    }
                }
                
                this.isIdleMotionPlaying = false;
            }
        }, 12000); // 12000ms = 12s
    }

    // 加载模型
    async loadModel(modelPath, options = {}) {
        console.log(`[Live2D] loadModel called with path: ${modelPath}`);
        if (!this.pixi_app) {
            throw new Error('PIXI 应用未初始化，请先调用 initPIXI()');
        }

        // 移除当前模型
        if (this.currentModel) {
            console.log('[Live2D] Removing existing model...');
            // 停止待机调度器
            this.stopIdleMotionScheduler();

            // 先清空常驻表情记录
            this.teardownPersistentExpressions();

            // 尝试还原之前覆盖的 updateParameters，避免旧引用在新模型上报错
            try {
                const mm = this.currentModel.internalModel && this.currentModel.internalModel.motionManager;
                if (mm) {
                    if (this._mouthOverrideInstalled && typeof this._origUpdateParameters === 'function') {
                        try { mm.updateParameters = this._origUpdateParameters; } catch (_) {}
                    }
                    if (mm && mm.expressionManager && this._mouthOverrideInstalled && typeof this._origExpressionUpdateParameters === 'function') {
                        try { mm.expressionManager.updateParameters = this._origExpressionUpdateParameters; } catch (_) {}
                    }
                }
            } catch (_) {}
            this._mouthOverrideInstalled = false;
            this._coreOverrideInstalled = false;
            
            // Remove previous ticker listeners if any
            if (this._overrideTickerListener && this.pixi_app && this.pixi_app.ticker) {
                this.pixi_app.ticker.remove(this._overrideTickerListener);
                this._overrideTickerListener = null;
            }
            this._origUpdateParameters = null;
            this._origExpressionUpdateParameters = null;
            // 同时移除 mouthTicker（若曾启用过 ticker 模式）
            if (this._mouthTicker && this.pixi_app && this.pixi_app.ticker) {
                try { this.pixi_app.ticker.remove(this._mouthTicker); } catch (_) {}
                this._mouthTicker = null;
            }

            // 移除由 HTML 锁图标或交互注册的监听，避免访问已销毁的显示对象
            try {
                // 先移除锁图标的 ticker 回调
                if (this._lockIconTicker && this.pixi_app && this.pixi_app.ticker) {
                    this.pixi_app.ticker.remove(this._lockIconTicker);
                }
                this._lockIconTicker = null;
                // 移除锁图标元素
                if (this._lockIconElement && this._lockIconElement.parentNode) {
                    this._lockIconElement.parentNode.removeChild(this._lockIconElement);
                }
                this._lockIconElement = null;
                
                // 清理浮动按钮系统
                if (this._floatingButtonsTicker && this.pixi_app && this.pixi_app.ticker) {
                    this.pixi_app.ticker.remove(this._floatingButtonsTicker);
                }
                this._floatingButtonsTicker = null;
                if (this._floatingButtonsContainer && this._floatingButtonsContainer.parentNode) {
                    this._floatingButtonsContainer.parentNode.removeChild(this._floatingButtonsContainer);
                }
                this._floatingButtonsContainer = null;
                this._floatingButtons = {};
                // 清理所有弹出框定时器
                Object.values(this._popupTimers).forEach(timer => clearTimeout(timer));
                this._popupTimers = {};
                
                // 暂停 ticker，期间做销毁，随后恢复
                this.pixi_app.ticker && this.pixi_app.ticker.stop();
            } catch (e) { console.warn('[Live2D] Error during cleanup prep:', e); }
            try {
                this.pixi_app.stage.removeAllListeners && this.pixi_app.stage.removeAllListeners();
            } catch (_) {}
            try {
                this.currentModel.removeAllListeners && this.currentModel.removeAllListeners();
            } catch (_) {}

            // 从舞台移除并销毁旧模型
            try { this.pixi_app.stage.removeChild(this.currentModel); } catch (_) {}
            try { this.currentModel.destroy({ children: true }); } catch (_) {}
            try { 
                this.pixi_app.ticker && this.pixi_app.ticker.start(); 
            } catch (_) {}
            console.log('[Live2D] Existing model removed.');
        }

        try {
            console.log('[Live2D] Starting model load...');
            if (!PIXI.live2d || !PIXI.live2d.Live2DModel) {
                throw new Error('PIXI.live2d.Live2DModel is not available. Library might not be loaded.');
            }
            
            let model;
            try {
                model = await PIXI.live2d.Live2DModel.from(modelPath, { autoInteract: false });
                console.log('[Live2D] Model loaded successfully.');
            } catch (loadError) {
                console.warn('模型加载失败，尝试回退到默认模型: mao_pro', loadError);
                if (modelPath !== '/static/mao_pro/mao_pro.model3.json') {
                    try {
                        const defaultPath = '/static/mao_pro/mao_pro.model3.json';
                        model = await PIXI.live2d.Live2DModel.from(defaultPath, { autoInteract: false });
                        console.log('成功回退到默认模型: mao_pro');
                    } catch (fallbackError) {
                        throw new Error(`原始模型加载失败: ${loadError.message}，且回退模型也失败: ${fallbackError.message}`);
                    }
                } else {
                    throw loadError;
                }
            }
            this.currentModel = model;

            // 解析模型目录名与根路径，供资源解析使用
            try {
                let urlString = null;
                if (typeof modelPath === 'string') {
                    urlString = modelPath;
                } else if (modelPath && typeof modelPath === 'object' && typeof modelPath.url === 'string') {
                    urlString = modelPath.url;
                }

                if (typeof urlString !== 'string') throw new TypeError('modelPath/url is not a string');

                const cleanPath = urlString.split('#')[0].split('?')[0];
                const lastSlash = cleanPath.lastIndexOf('/');
                const rootDir = lastSlash >= 0 ? cleanPath.substring(0, lastSlash) : '/static';
                this.modelRootPath = rootDir; // e.g. /static/mao_pro or /static/some/deeper/dir
                const parts = rootDir.split('/').filter(Boolean);
                this.modelName = parts.length > 0 ? parts[parts.length - 1] : null;
                console.log('模型根路径解析:', { modelUrl: urlString, modelName: this.modelName, modelRootPath: this.modelRootPath });
            } catch (e) {
                console.warn('解析模型根路径失败，将使用默认值', e);
                this.modelRootPath = '/static';
                this.modelName = null;
            }

            // 配置渲染纹理数量以支持更多蒙版
            if (model.internalModel && model.internalModel.renderer && model.internalModel.renderer._clippingManager) {
                model.internalModel.renderer._clippingManager._renderTextureCount = 3;
                if (typeof model.internalModel.renderer._clippingManager.initialize === 'function') {
                    model.internalModel.renderer._clippingManager.initialize(
                        model.internalModel.coreModel,
                        model.internalModel.coreModel.getDrawableCount(),
                        model.internalModel.coreModel.getDrawableMasks(),
                        model.internalModel.coreModel.getDrawableMaskCounts(),
                        3
                    );
                }
                console.log('渲染纹理数量已设置为3');
            }

            // 应用位置和缩放设置
            this.applyModelSettings(model, options);

            // 添加到舞台
            console.log('[Live2D] Adding model to stage...');
            this.pixi_app.stage.addChild(model);
            console.log('[Live2D] Model added to stage.');

            // [DEBUG] 打印模型参数
            this.logModelParameters(model);

            // 设置交互性
            if (options.dragEnabled !== false) {
                this.setupDragAndDrop(model);
            }

            // 设置滚轮缩放
            if (options.wheelEnabled !== false) {
                this.setupWheelZoom(model);
            }
            
            // 设置触摸缩放（双指捏合）
            if (options.touchZoomEnabled !== false) {
                this.setupTouchZoom(model);
            }

            // 启用鼠标跟踪
            if (options.mouseTracking !== false) {
                this.enableMouseTracking(model);
            }

            // 设置浮动按钮系统（在模型完全就绪后再绑定ticker回调）
            this.setupFloatingButtons(model);
            
            // 设置原来的锁按钮
            this.setupHTMLLockIcon(model);

            // 安装核心参数覆盖系统（用于强制控制眼睛等参数 + 智能叠加）
            try {
                this.installCoreOverride();
                console.log('已安装核心参数覆盖（含智能叠加）');
            } catch (e) {
                console.warn('安装核心参数覆盖失败:', e);
            }

            // 加载 FileReferences 与 EmotionMapping
            if (options.loadEmotionMapping !== false) {
                const settings = model.internalModel && model.internalModel.settings && model.internalModel.settings.json;
                if (settings) {
                    // 保存原始 FileReferences
                    this.fileReferences = settings.FileReferences || null;

                    // 优先使用顶层 EmotionMapping，否则从 FileReferences 推导
                    if (settings.EmotionMapping && (settings.EmotionMapping.expressions || settings.EmotionMapping.motions)) {
                        this.emotionMapping = settings.EmotionMapping;
                    } else {
                        this.emotionMapping = this.deriveEmotionMappingFromFileRefs(this.fileReferences || {});
                    }
                    console.log('已加载情绪映射:', this.emotionMapping);
                } else {
                    console.warn('模型配置中未找到 settings.json，无法加载情绪映射');
                }
            }

            // 先从服务器同步映射（覆盖“常驻”），再设置常驻表情
            try { await this.syncEmotionMappingWithServer({ replacePersistentOnly: true }); } catch(_) {}
            
            // [Auto-Adaptation] Run discovery after loading mapping
            // This merges discovered mappings with existing config
            this.autoDiscoverMappings();

            // 设置常驻表情（根据 EmotionMapping.expressions.常驻 或 FileReferences 前缀推导）
            await this.setupPersistentExpressions();

            // Update compatibility references
            if (!window.LanLan1) window.LanLan1 = {};
            window.LanLan1.live2dModel = model;
            window.LanLan1.currentModel = model;
            window.LanLan1.emotionMapping = this.emotionMapping;
            console.log('[Live2D] Updated window.LanLan1 references');

            // 启动待机动作调度器
            this.startIdleMotionScheduler();

            // 调用回调函数
            if (this.onModelLoaded) {
                this.onModelLoaded(model, modelPath);
            }

            return model;
        } catch (error) {
            console.error('加载模型失败:', error);
            throw error;
        }
    }

    // 不再需要预解析嘴巴参数ID，保留占位以兼容旧代码调用
    resolveMouthParameterId() { return null; }



    // 解析资源相对路径（基于当前模型根目录）
    resolveAssetPath(relativePath) {
        if (!relativePath) return '';
        let rel = String(relativePath).replace(/^[\\/]+/, '');
        if (rel.startsWith('static/')) {
            return `/${rel}`;
        }
        if (rel.startsWith('/static/')) {
            return rel;
        }
        return `${this.modelRootPath}/${rel}`;
    }

    // 应用模型设置
    applyModelSettings(model, options) {
        const { preferences, isMobile = false } = options;

        if (isMobile) {
            // 移动端设置
            const scale = Math.min(
                0.5,
                window.innerHeight * 1.3 / 4000,
                window.innerWidth * 1.2 / 2000
            );
            model.scale.set(scale);
            model.x = this.pixi_app.renderer.width * 0.5;
            model.y = this.pixi_app.renderer.height * 0.28;
            model.anchor.set(0.5, 0.1);
        } else {
            // 桌面端设置
            if (preferences && preferences.scale && preferences.position) {
                // 使用保存的偏好设置
                model.scale.set(preferences.scale.x, preferences.scale.y);
                model.x = preferences.position.x;
                model.y = preferences.position.y;
            } else {
                // 使用默认设置 - 模型居中显示，确保完整可见
                // 假设标准模型高度约 3000-4000 单位
                const width = window.innerWidth;
                const height = window.innerHeight;
                
                // 根据画布尺寸计算合适的缩放比例，确保模型完整显示
                const scale = Math.min(
                    0.2, 
                    (height * 0.7) / 3500,
                    (width * 0.8) / 2000
                );
                model.scale.set(scale);
                
                // 水平居中，垂直居中偏下
                model.x = width * 0.5;
                model.y = height * 0.55;
                
                // 锚点设为中心 (0.5, 0.5)
                model.anchor.set(0.5, 0.5);
                
                console.log(`[Live2D] Applied settings: scale=${scale}, x=${model.x}, y=${model.y}, screen=${width}x${height}`);
            }
        }
        
        // 默认看向正前方
        try {
            model.focus(0, 0);
        } catch (e) {
            console.warn('[Live2D] Failed to reset focus:', e);
        }
    }

    // 设置拖拽功能
    setupDragAndDrop(model) {
        model.interactive = true;
        this.pixi_app.stage.interactive = true;
        this.pixi_app.stage.hitArea = this.pixi_app.screen;

        let isDragging = false;
        let dragStartPos = new PIXI.Point();

        model.on('pointerdown', (event) => {
            if (this.isLocked) return;
            
            // 检测是否为触摸事件，且是多点触摸（双指缩放）
            const originalEvent = event.data.originalEvent;
            if (originalEvent && originalEvent.touches && originalEvent.touches.length > 1) {
                // 多点触摸时不启动拖拽
                return;
            }
            
            isDragging = true;
            this.isFocusing = false; // 拖拽时禁用聚焦
            const globalPos = event.data.global;
            dragStartPos.x = globalPos.x - model.x;
            dragStartPos.y = globalPos.y - model.y;
            document.getElementById('live2d-canvas').style.cursor = 'grabbing';
        });

        const onDragEnd = () => {
            if (isDragging) {
                isDragging = false;
                document.getElementById('live2d-canvas').style.cursor = 'grab';
            }
        };

        this.pixi_app.stage.on('pointerup', onDragEnd);
        this.pixi_app.stage.on('pointerupoutside', onDragEnd);

        this.pixi_app.stage.on('pointermove', (event) => {
            if (isDragging) {
                // 再次检查是否变成多点触摸
                const originalEvent = event.data.originalEvent;
                if (originalEvent && originalEvent.touches && originalEvent.touches.length > 1) {
                    // 如果变成多点触摸，停止拖拽
                    isDragging = false;
                    document.getElementById('live2d-canvas').style.cursor = 'grab';
                    return;
                }
                
                const newPosition = event.data.global;
                model.x = newPosition.x - dragStartPos.x;
                model.y = newPosition.y - dragStartPos.y;
            }
        });
    }

    // 设置滚轮缩放
    setupWheelZoom(model) {
        const onWheelScroll = (event) => {
            if (this.isLocked || !this.currentModel) return;
            event.preventDefault();
            const scaleFactor = 1.1;
            const oldScale = this.currentModel.scale.x;
            let newScale = event.deltaY < 0 ? oldScale * scaleFactor : oldScale / scaleFactor;
            this.currentModel.scale.set(newScale);
        };

        const view = this.pixi_app.view;
        if (view.lastWheelListener) {
            view.removeEventListener('wheel', view.lastWheelListener);
        }
        view.addEventListener('wheel', onWheelScroll, { passive: false });
        view.lastWheelListener = onWheelScroll;
    }
    
    // 设置触摸缩放（双指捏合）
    setupTouchZoom(model) {
        const view = this.pixi_app.view;
        let initialDistance = 0;
        let initialScale = 1;
        let isTouchZooming = false;
        
        const getTouchDistance = (touch1, touch2) => {
            const dx = touch2.clientX - touch1.clientX;
            const dy = touch2.clientY - touch1.clientY;
            return Math.sqrt(dx * dx + dy * dy);
        };
        
        const onTouchStart = (event) => {
            if (this.isLocked || !this.currentModel) return;
            
            // 检测双指触摸
            if (event.touches.length === 2) {
                event.preventDefault();
                isTouchZooming = true;
                initialDistance = getTouchDistance(event.touches[0], event.touches[1]);
                initialScale = this.currentModel.scale.x;
            }
        };
        
        const onTouchMove = (event) => {
            if (this.isLocked || !this.currentModel || !isTouchZooming) return;
            
            // 双指缩放
            if (event.touches.length === 2) {
                event.preventDefault();
                const currentDistance = getTouchDistance(event.touches[0], event.touches[1]);
                const scaleChange = currentDistance / initialDistance;
                let newScale = initialScale * scaleChange;
                
                // 限制缩放范围，避免过大或过小
                newScale = Math.max(0.1, Math.min(2.0, newScale));
                
                this.currentModel.scale.set(newScale);
            }
        };
        
        const onTouchEnd = (event) => {
            // 当手指数量小于2时，停止缩放
            if (event.touches.length < 2) {
                isTouchZooming = false;
            }
        };
        
        // 移除旧的监听器（如果存在）
        if (view.lastTouchStartListener) {
            view.removeEventListener('touchstart', view.lastTouchStartListener);
        }
        if (view.lastTouchMoveListener) {
            view.removeEventListener('touchmove', view.lastTouchMoveListener);
        }
        if (view.lastTouchEndListener) {
            view.removeEventListener('touchend', view.lastTouchEndListener);
        }
        
        // 添加新的监听器
        view.addEventListener('touchstart', onTouchStart, { passive: false });
        view.addEventListener('touchmove', onTouchMove, { passive: false });
        view.addEventListener('touchend', onTouchEnd, { passive: false });
        
        // 保存监听器引用，便于清理
        view.lastTouchStartListener = onTouchStart;
        view.lastTouchMoveListener = onTouchMove;
        view.lastTouchEndListener = onTouchEnd;
    }
    
    // 设置 HTML 锁形图标（保留用于兼容）
    setupHTMLLockIcon(model) {
        // 已集成到浮动按钮中，不再单独创建
        return;
        
        /*
        const container = document.getElementById('live2d-canvas');
        
        // 在 l2d_manager 等页面，默认解锁并可交互
        if (!document.getElementById('chat-container')) {
            this.isLocked = false;
            container.style.pointerEvents = 'auto';
            return;
        }

        const lockIcon = document.createElement('div');
        lockIcon.id = 'live2d-lock-icon';
        lockIcon.innerText = this.isLocked ? '🔒' : '🔓';
        Object.assign(lockIcon.style, {
            position: 'fixed',
            zIndex: '30',
            fontSize: '24px',
            cursor: 'pointer',
            userSelect: 'none',
            textShadow: '0 0 4px black',
            pointerEvents: 'auto',
            display: 'none' // 默认隐藏
        });

        document.body.appendChild(lockIcon);
        this._lockIconElement = lockIcon;

        lockIcon.addEventListener('click', (e) => {
            e.stopPropagation();
            this.isLocked = !this.isLocked;
            lockIcon.innerText = this.isLocked ? '🔒' : '🔓';

            if (this.isLocked) {
                container.style.pointerEvents = 'none';
            } else {
                container.style.pointerEvents = 'auto';
            }
        });

        // 初始状态
        container.style.pointerEvents = this.isLocked ? 'none' : 'auto';

        // 持续更新图标位置（保存回调用于移除）
        const tick = () => {
            try {
                if (!model || !model.parent) {
                    // 模型可能已被销毁或从舞台移除
                    if (lockIcon) lockIcon.style.display = 'none';
                    return;
                }
                const bounds = model.getBounds();
                const screenWidth = window.innerWidth;
                const screenHeight = window.innerHeight;

                const targetX = bounds.right * 0.7 + bounds.left * 0.3;
                const targetY = bounds.top * 0.3 + bounds.bottom * 0.7;

                lockIcon.style.left = `${Math.min(targetX, screenWidth - 40)}px`;
                lockIcon.style.top = `${Math.min(targetY, screenHeight - 40)}px`;
            } catch (_) {
                // 忽略单帧异常
            }
        };
        this._lockIconTicker = tick;
        this.pixi_app.ticker.add(tick);
        */
    }

    // 设置浮动按钮系统（新的控制面板）
    setupFloatingButtons(model) {
        // 检查 URL 参数以识别是否处于独立浮窗模式，但允许在应用内也显示 JS 按钮
        const urlParams = new URLSearchParams(window.location.search);
        const isFloating = urlParams.get('floating') === 'true';
        const controlsParam = urlParams.get('controls');

        // Logic:
        // 1. If controls explicitly set to 'false', HIDE.
        // 2. If controls explicitly set to 'true', SHOW.
        // 3. If controls not set, fallback to old logic (Hide if floating).

        if (controlsParam === 'false') {
             console.log('[Live2D] Controls explicitly disabled via URL.');
             return;
        }

        if (controlsParam === 'true') {
            console.log('[Live2D] Controls explicitly enabled via URL.');
            // Proceed to show buttons
        } else {
            // Fallback
            if (isFloating) {
                console.log('[Live2D] Floating mode detected (no controls param): Hiding Web-based floating buttons.');
                return;
            }
        }

        const container = document.getElementById('live2d-canvas');
        
        // 在 l2d_manager 等页面不显示 (通过检测特定元素或URL判断)
        // 如果是 index.html (通常用于展示)，则应该显示工具栏
        // 简单判断：如果 URL 包含 'manager' 或 'editor' 则不显示
        if (window.location.href.includes('manager') || window.location.href.includes('editor')) {
            this.isLocked = false;
            container.style.pointerEvents = 'auto';
            return;
        }

        // 创建按钮容器
        const buttonsContainer = document.createElement('div');
        buttonsContainer.id = 'live2d-floating-buttons';
        // 基础样式（交互由内部按钮接管 pointer-events）
        Object.assign(buttonsContainer.style, {
            position: 'fixed',
            zIndex: '30',
            pointerEvents: 'none',
            display: 'none', // 初始隐藏，鼠标靠近时才显示
            gap: '12px',
            padding: '10px',
            borderRadius: '30px',
        });

        // 响应式布局：窄窗口时改为竖向靠右显示，宽窗口时居中横向显示
        if (window.innerWidth <= 420) {
            buttonsContainer.style.flexDirection = 'column';
            buttonsContainer.style.top = '12px';
            buttonsContainer.style.right = '12px';
            buttonsContainer.style.left = 'auto';
            buttonsContainer.style.transform = 'none';
        } else {
            buttonsContainer.style.flexDirection = 'row';
            buttonsContainer.style.top = '20px';
            buttonsContainer.style.left = '50%';
            buttonsContainer.style.transform = 'translateX(-50%)';
        }
        document.body.appendChild(buttonsContainer);
        this._floatingButtonsContainer = buttonsContainer;

        // 定义按钮配置（从上到下：设置、锁定、重载）
        // 移除了 N.E.K.O. 项目特定的云服务功能（麦克风、屏幕分享、Agent工具）
        // 移除了关闭按钮，使用 Windows 原生关闭
        const buttonConfigs = [
            { id: 'settings', emoji: '⚙️', title: '设置', hasPopup: true, popupToggle: true },
            { id: 'lock', emoji: this.isLocked ? '🔒' : '🔓', title: '锁定位置', hasPopup: false },
            { id: 'reload', emoji: '🔄', title: '重载模型', hasPopup: false }
        ];

        // 创建主按钮
        buttonConfigs.forEach(config => {
            const btnWrapper = document.createElement('div');
            btnWrapper.style.position = 'relative';
            btnWrapper.style.display = 'flex';
            btnWrapper.style.alignItems = 'center';
            btnWrapper.style.gap = '8px';

            const btn = document.createElement('div');
            btn.id = `live2d-btn-${config.id}`;
            btn.className = 'live2d-floating-btn';
            btn.innerText = config.emoji;
            btn.title = config.title;
            
            Object.assign(btn.style, {
                width: '48px',
                height: '48px',
                borderRadius: '50%',
                background: 'rgba(255, 255, 255, 0.9)',
                backdropFilter: 'blur(10px)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: '24px',
                cursor: 'pointer',
                userSelect: 'none',
                boxShadow: '0 2px 8px rgba(0, 0, 0, 0.2)',
                transition: 'all 0.2s ease',
                pointerEvents: 'auto'
            });

            // 鼠标悬停效果
            btn.addEventListener('mouseenter', () => {
                btn.style.transform = 'scale(1.1)';
                btn.style.boxShadow = '0 4px 12px rgba(0, 0, 0, 0.3)';
            });
            btn.addEventListener('mouseleave', () => {
                btn.style.transform = 'scale(1)';
                btn.style.boxShadow = '0 2px 8px rgba(0, 0, 0, 0.2)';
            });

            // popupToggle: 按钮点击切换弹出框显示，弹出框显示时按钮变蓝
            if (config.popupToggle) {
                const popup = this.createPopup(config.id);
                btnWrapper.appendChild(btn);
                
                // 直接将弹出框添加到btnWrapper，这样定位更准确
                btnWrapper.appendChild(popup);
                
                btn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    
                    // 检查弹出框当前状态
                    const isPopupVisible = popup.style.display === 'flex' && popup.style.opacity === '1';
                    
                    // 实现互斥逻辑：如果有exclusive配置，关闭对方
                    if (!isPopupVisible && config.exclusive) {
                        const exclusiveBtn = this._floatingButtons[config.exclusive];
                        if (exclusiveBtn) {
                            const exclusivePopup = document.getElementById(`live2d-popup-${config.exclusive}`);
                            if (exclusivePopup && exclusivePopup.style.display === 'flex') {
                                // 关闭对方的弹出框
                                exclusivePopup.style.opacity = '0';
                                exclusivePopup.style.transform = 'translateX(-10px)';
                                setTimeout(() => {
                                    exclusivePopup.style.display = 'none';
                                }, 200);
                                // 对方按钮恢复白色
                                exclusiveBtn.button.style.background = 'rgba(255, 255, 255, 0.9)';
                            }
                        }
                    }
                    
                    // 切换弹出框
                    this.showPopup(config.id, popup);
                    
                    // 等待弹出框状态更新后设置按钮颜色（异步操作完成后）
                    setTimeout(() => {
                        const newPopupVisible = popup.style.display === 'flex' && popup.style.opacity === '1';
                        btn.style.background = newPopupVisible ? 
                            'rgba(79, 140, 255, 0.9)' : 
                            'rgba(255, 255, 255, 0.9)';
                    }, 50);
                });
                
            } else if (config.toggle) {
                // Toggle 状态（可能同时有弹出框）
                btn.dataset.active = 'false';
                
                btn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    const isActive = btn.dataset.active === 'true';
                    btn.dataset.active = (!isActive).toString();
                    btn.style.background = !isActive ? 
                        'rgba(79, 140, 255, 0.9)' : 
                        'rgba(255, 255, 255, 0.9)';
                    
                    // 触发自定义事件
                    const event = new CustomEvent(`live2d-${config.id}-toggle`, {
                        detail: { active: !isActive }
                    });
                    window.dispatchEvent(event);
                });
                
                // 先添加主按钮到包装器
                btnWrapper.appendChild(btn);
                
                // 如果有弹出框且需要独立的触发器（仅麦克风）
                if (config.hasPopup && config.separatePopupTrigger) {
                    const popup = this.createPopup(config.id);
                    
                    // 创建三角按钮（用于触发弹出框）
                    const triggerBtn = document.createElement('div');
                    triggerBtn.innerText = '▶';
                    Object.assign(triggerBtn.style, {
                        width: '24px',
                        height: '24px',
                        borderRadius: '50%',
                        background: 'rgba(255, 255, 255, 0.9)',
                        backdropFilter: 'blur(10px)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        fontSize: '12px',
                        cursor: 'pointer',
                        userSelect: 'none',
                        boxShadow: '0 2px 8px rgba(0, 0, 0, 0.2)',
                        transition: 'all 0.2s ease',
                        pointerEvents: 'auto',
                        marginLeft: '-10px'
                    });
                    
                    triggerBtn.addEventListener('mouseenter', () => {
                        triggerBtn.style.transform = 'scale(1.1)';
                        triggerBtn.style.boxShadow = '0 4px 12px rgba(0, 0, 0, 0.3)';
                    });
                    triggerBtn.addEventListener('mouseleave', () => {
                        triggerBtn.style.transform = 'scale(1)';
                        triggerBtn.style.boxShadow = '0 2px 8px rgba(0, 0, 0, 0.2)';
                    });
                    
                    triggerBtn.addEventListener('click', async (e) => {
                        e.stopPropagation();
                        
                        // 如果是麦克风弹出框，先加载麦克风列表
                        if (config.id === 'mic' && window.renderFloatingMicList) {
                            await window.renderFloatingMicList();
                        }
                        
                        this.showPopup(config.id, popup);
                    });
                    
                    // 创建包装器用于三角按钮和弹出框（相对定位）
                    const triggerWrapper = document.createElement('div');
                    triggerWrapper.style.position = 'relative';
                    triggerWrapper.appendChild(triggerBtn);
                    triggerWrapper.appendChild(popup);
                    
                    btnWrapper.appendChild(triggerWrapper);
                }
            } else {
                // 普通点击按钮
                btnWrapper.appendChild(btn);
                btn.addEventListener('click', (e) => {
                    e.stopPropagation();
                    
                    // 处理内置功能
                    if (config.id === 'reload') {
                        window.location.reload();
                        return;
                    }
                    if (config.id === 'goodbye') {
                        // 尝试关闭窗口 (针对独立悬浮窗)
                        // 1. 尝试标准 window.close()
                        window.close();
                        // 2. 尝试 WebView2 postMessage (针对 desktop_webview_window)
                        if (window.chrome && window.chrome.webview) {
                            window.chrome.webview.postMessage('close');
                        }
                        // 3. 发送事件给 Flutter (作为后备)
                        const event = new CustomEvent('live2d-close-window');
                        window.dispatchEvent(event);
                        return;
                    }
                    if (config.id === 'lock') {
                        this.isLocked = !this.isLocked;
                        btn.innerText = this.isLocked ? '🔒' : '🔓';
                        // 移除对 container.style.pointerEvents 的修改，
                        // 因为这会禁用所有交互（包括点击），而我们只想禁用拖拽。
                        // 拖拽逻辑在 setupDragAndDrop 中已经检查了 this.isLocked。
                        
                        // 同步更新旧的锁图标（如果存在）
                        if (this._lockIconElement) {
                            this._lockIconElement.innerText = this.isLocked ? '🔒' : '🔓';
                        }
                        return;
                    }

                    const event = new CustomEvent(`live2d-${config.id}-click`);
                    window.dispatchEvent(event);
                });
            }

            buttonsContainer.appendChild(btnWrapper);
            this._floatingButtons[config.id] = { button: btn, wrapper: btnWrapper };
        });

        console.log('[Live2D] 所有浮动按钮已创建完成');

        // 初始状态
        container.style.pointerEvents = this.isLocked ? 'none' : 'auto';

        // 不再需要持续更新位置，因为现在是顶部固定居中
        /*
        const tick = () => { ... };
        this._floatingButtonsTicker = tick;
        this.pixi_app.ticker.add(tick);
        */
        
        // 页面加载时先显示5秒
        setTimeout(() => {
            // 只有在未点击"请她离开"时才显示
            if (!this._goodbyeClicked) {
                buttonsContainer.style.display = 'flex';
                setTimeout(() => {
                    // 5秒后如果鼠标不在顶部区域且未点击"请她离开"就隐藏
                    // 注意：这里不再依赖 isFocusing (模型聚焦)，而是依赖鼠标位置
                    if (!this._isMouseInToolbarArea && !this._goodbyeClicked) {
                        buttonsContainer.style.display = 'none';
                    }
                }, 5000);
            }
        }, 100); // 延迟100ms确保位置已计算
    }

    // 创建弹出框
    createPopup(buttonId) {
        const popup = document.createElement('div');
        popup.id = `live2d-popup-${buttonId}`;
        popup.className = 'live2d-popup';
        
        Object.assign(popup.style, {
            position: 'absolute',
            left: '50%',
            top: '100%',
            marginTop: '12px',
            marginLeft: '0',
            background: 'rgba(255, 255, 255, 0.95)',
            backdropFilter: 'blur(10px)',
            borderRadius: '12px',
            padding: '8px',
            boxShadow: '0 2px 12px rgba(0, 0, 0, 0.2)',
            display: 'none',
            flexDirection: 'column',
            gap: '6px',
            minWidth: '180px',
            maxHeight: '200px',
            overflowY: 'auto',
            pointerEvents: 'auto',
            opacity: '0',
            transform: 'translateX(-50%) translateY(-10px)',
            transition: 'opacity 0.2s ease, transform 0.2s ease'
        });

        // 根据不同按钮创建不同的弹出内容
        if (buttonId === 'settings') {
            // 检查是否在独立悬浮窗模式
            const urlParams = new URLSearchParams(window.location.search);
            const isFloating = urlParams.get('floating') === 'true';

            // 如果不是独立悬浮窗（即在软件内），点击设置应跳转到软件设置
            // 但由于这是 Web 内部的 popup 创建逻辑，我们可以在按钮点击时拦截
            // 见 setupFloatingButtons 中的 click handler
            
            // 设置菜单内容构建...
            
            // 先添加 Focus 模式、主动搭话、眼神跟随开关
            const settingsToggles = [
                { id: 'focus-mode', label: '🎯 允许打断', storageKey: 'focusModeEnabled', inverted: true },
                { id: 'proactive-chat', label: '💬 主动搭话', storageKey: 'proactiveChatEnabled' }
            ];

            // 只有在非浮窗模式下才显示眼神跟随开关 (因为浮窗模式下通常有系统级控制或不需要，避免冲突)
            if (!isFloating) {
                settingsToggles.push({ id: 'mouse-tracking', label: '👀 眼神跟随', storageKey: 'mouseTrackingEnabled' });
            }
            
            settingsToggles.forEach(toggle => {
                const toggleItem = document.createElement('div');
                Object.assign(toggleItem.style, {
                    display: 'flex',
                    alignItems: 'center',
                    gap: '8px',
                    padding: '6px 8px',
                    cursor: 'pointer',
                    borderRadius: '6px',
                    transition: 'background 0.2s ease',
                    fontSize: '13px',
                    whiteSpace: 'nowrap',
                    borderBottom: '1px solid rgba(0,0,0,0.05)'
                });
                
                const checkbox = document.createElement('input');
                checkbox.type = 'checkbox';
                checkbox.id = `live2d-${toggle.id}`;
                checkbox.style.cursor = 'pointer';
                
                // 初始化状态
                if (toggle.id === 'focus-mode' && typeof window.focusModeEnabled !== 'undefined') {
                    checkbox.checked = toggle.inverted ? !window.focusModeEnabled : window.focusModeEnabled;
                } else if (toggle.id === 'proactive-chat' && typeof window.proactiveChatEnabled !== 'undefined') {
                    checkbox.checked = window.proactiveChatEnabled;
                } else if (toggle.id === 'mouse-tracking') {
                    checkbox.checked = this.mouseTrackingEnabled;
                }
                
                const label = document.createElement('label');
                label.innerText = toggle.label;
                label.htmlFor = `live2d-${toggle.id}`;
                label.style.cursor = 'pointer';
                label.style.userSelect = 'none';
                label.style.fontSize = '13px';
                label.style.flex = '1';
                
                toggleItem.appendChild(checkbox);
                toggleItem.appendChild(label);
                popup.appendChild(toggleItem);
                
                toggleItem.addEventListener('mouseenter', () => {
                    toggleItem.style.background = 'rgba(79, 140, 255, 0.1)';
                });
                toggleItem.addEventListener('mouseleave', () => {
                    toggleItem.style.background = 'transparent';
                });
                
                // 点击切换
                checkbox.addEventListener('change', (e) => {
                    e.stopPropagation();
                    const isChecked = checkbox.checked;
                    
                    if (toggle.id === 'focus-mode') {
                        const actualValue = toggle.inverted ? !isChecked : isChecked;
                        const appCheckbox = document.getElementById('focus-mode-toggle-l2d');
                        if (appCheckbox && appCheckbox.checked !== actualValue) {
                            appCheckbox.checked = actualValue;
                            appCheckbox.dispatchEvent(new Event('change', { bubbles: true }));
                        } else if (!appCheckbox) {
                            window.focusModeEnabled = actualValue;
                            console.log(`允许打断已${isChecked ? '开启' : '关闭'}（focusModeEnabled=${actualValue}）`);
                        }
                    } else if (toggle.id === 'proactive-chat') {
                        const appCheckbox = document.getElementById('proactive-chat-toggle-l2d');
                        if (appCheckbox && appCheckbox.checked !== isChecked) {
                            appCheckbox.checked = isChecked;
                            appCheckbox.dispatchEvent(new Event('change', { bubbles: true }));
                        } else if (!appCheckbox) {
                            window.proactiveChatEnabled = isChecked;
                            if (isChecked && typeof window.resetProactiveChatBackoff === 'function') {
                                window.resetProactiveChatBackoff();
                            } else if (!isChecked && typeof window.stopProactiveChatSchedule === 'function') {
                                window.stopProactiveChatSchedule();
                            }
                            console.log(`主动搭话已${isChecked ? '开启' : '关闭'}`);
                        }
                    } else if (toggle.id === 'mouse-tracking') {
                        this.mouseTrackingEnabled = isChecked;
                        console.log(`眼神跟随已${isChecked ? '开启' : '关闭'}`);
                        // 如果关闭，重置视线到中心
                        if (!isChecked && this.currentModel) {
                            this.currentModel.focus(0, 0);
                        }
                    }
                });
                
                toggleItem.addEventListener('click', (e) => {
                    // 如果点击的是复选框或标签，让原生行为处理（避免双重触发）
                    if (e.target === checkbox || e.target === label) {
                        return;
                    }
                    
                    // 点击容器其他区域时手动切换
                    checkbox.checked = !checkbox.checked;
                    checkbox.dispatchEvent(new Event('change', { bubbles: true }));
                });
            });
            
            // 添加分隔线 (已移除，因为下方菜单项已移除)
            /*
            const separator = document.createElement('div');
            Object.assign(separator.style, {
                height: '1px',
                background: 'rgba(0,0,0,0.1)',
                margin: '4px 0'
            });
            popup.appendChild(separator);
            */
            
            // 然后添加导航菜单项
            // [Cleanup] 移除了 N.E.K.O. 项目特定的云服务页面链接
            // 这些设置现在统一在 Flutter 客户端中管理
            const settingsItems = [];
            
            /*
            settingsItems.forEach(item => {
                const menuItem = document.createElement('div');
                Object.assign(menuItem.style, {
                    padding: '8px 12px',
                    cursor: 'pointer',
                    borderRadius: '6px',
                    transition: 'background 0.2s ease',
                    fontSize: '13px',
                    whiteSpace: 'nowrap'
                });
                menuItem.innerText = item.label;
                
                menuItem.addEventListener('mouseenter', () => {
                    menuItem.style.background = 'rgba(79, 140, 255, 0.1)';
                });
                menuItem.addEventListener('mouseleave', () => {
                    menuItem.style.background = 'transparent';
                });
                
                menuItem.addEventListener('click', (e) => {
                    e.stopPropagation();
                    if (item.action === 'navigate') {
                        // 动态构建 URL（点击时才获取 lanlan_name）
                        let finalUrl = item.url || item.urlBase;
                        if (item.id === 'live2d-manage' && item.urlBase) {
                            // 从 window.lanlan_config 动态获取 lanlan_name
                            const lanlanName = (window.lanlan_config && window.lanlan_config.lanlan_name) || '';
                            finalUrl = `${item.urlBase}?lanlan_name=${encodeURIComponent(lanlanName)}`;
                            // Live2D设置页直接跳转
                            window.location.href = finalUrl;
                        } else {
                            // 其他页面弹出新窗口
                            window.open(finalUrl, '_blank', 'width=1000,height=800,menubar=no,toolbar=no,location=no,status=no');
                        }
                    }
                });
                
                popup.appendChild(menuItem);
            });
            */
        }

        return popup;
    }

    // 显示弹出框（1秒后自动隐藏），支持点击切换
    showPopup(buttonId, popup) {
        // 检查当前状态
        const isVisible = popup.style.display === 'flex' && popup.style.opacity === '1';
        
        // 清除之前的定时器
        if (this._popupTimers[buttonId]) {
            clearTimeout(this._popupTimers[buttonId]);
            this._popupTimers[buttonId] = null;
        }
        
        // 如果是设置弹出框，每次显示时更新开关状态（确保与 app.js 同步）
        if (buttonId === 'settings') {
            const focusCheckbox = popup.querySelector('#live2d-focus-mode');
            const proactiveChatCheckbox = popup.querySelector('#live2d-proactive-chat');
            const mouseTrackingCheckbox = popup.querySelector('#live2d-mouse-tracking');
            
            if (focusCheckbox && typeof window.focusModeEnabled !== 'undefined') {
                // "允许打断"按钮值与 focusModeEnabled 相反
                focusCheckbox.checked = !window.focusModeEnabled;
            }
            if (proactiveChatCheckbox && typeof window.proactiveChatEnabled !== 'undefined') {
                proactiveChatCheckbox.checked = window.proactiveChatEnabled;
            }
            if (mouseTrackingCheckbox) {
                mouseTrackingCheckbox.checked = this.mouseTrackingEnabled;
            }
        }
        
        if (isVisible) {
            // 如果已经显示，则隐藏
            popup.style.opacity = '0';
            popup.style.transform = 'translateX(-50%) translateY(-10px)';
            setTimeout(() => {
                popup.style.display = 'none';
                // 重置位置
                popup.style.left = '50%';
                popup.style.top = '100%';
            }, 200);
        } else {
            // 如果隐藏，则显示
            popup.style.display = 'flex';
            // 先让弹出框可见但透明，以便计算尺寸
            popup.style.opacity = '0';
            popup.style.visibility = 'visible';
            
            // 等待一帧让浏览器计算布局
            setTimeout(() => {
                // 显示弹出框
                popup.style.visibility = 'visible';
                popup.style.opacity = '1';
                popup.style.transform = 'translateX(-50%) translateY(0)';
            }, 10);
            
            // 设置、agent、麦克风弹出框不自动隐藏，其他的1秒后隐藏
            if (buttonId !== 'settings' && buttonId !== 'agent' && buttonId !== 'mic') {
                this._popupTimers[buttonId] = setTimeout(() => {
                    popup.style.opacity = '0';
                    popup.style.transform = 'translateX(-50%) translateY(-10px)';
                    setTimeout(() => {
                        popup.style.display = 'none';
                        // 重置位置
                        popup.style.left = '50%';
                        popup.style.top = '100%';
                    }, 200);
                    this._popupTimers[buttonId] = null;
                }, 1000);
            }
        }
    }

    // 启用鼠标跟踪以检测与模型的接近度
    enableMouseTracking(model, options = {}) {
        const { threshold = 70 } = options;
        let hideButtonsTimer = null;

        // 全局鼠标移动监听（用于顶部工具栏）
        window.addEventListener('mousemove', (event) => {
            const floatingButtons = document.getElementById('live2d-floating-buttons');
            if (!floatingButtons || this._goodbyeClicked) return;

            // 检测鼠标是否在顶部区域 (y < 100) 或在工具栏上
            const isTopArea = event.clientY < 100;
            
            // 检查鼠标是否在工具栏元素内部
            const rect = floatingButtons.getBoundingClientRect();
            const isInToolbar = (
                event.clientX >= rect.left && 
                event.clientX <= rect.right && 
                event.clientY >= rect.top && 
                event.clientY <= rect.bottom
            );

            // 检查是否有任何弹出菜单是打开的
            const isAnyPopupOpen = Object.keys(this._floatingButtons).some(key => {
                const popup = document.getElementById(`live2d-popup-${key}`);
                return popup && popup.style.display !== 'none';
            });

            if (isTopArea || isInToolbar || isAnyPopupOpen) {
                this._isMouseInToolbarArea = true;
                floatingButtons.style.display = 'flex';
                
                if (hideButtonsTimer) {
                    clearTimeout(hideButtonsTimer);
                    hideButtonsTimer = null;
                }
            } else {
                this._isMouseInToolbarArea = false;
                // 离开区域后延迟隐藏（延迟改为1秒以匹配 UX 需求）
                if (!hideButtonsTimer) {
                    hideButtonsTimer = setTimeout(() => {
                        // 再次检查，防止在延迟期间鼠标又移回去了
                        const stillOpen = Object.keys(this._floatingButtons).some(key => {
                            const popup = document.getElementById(`live2d-popup-${key}`);
                            return popup && popup.style.display !== 'none';
                        });
                        
                        if (!this._isMouseInToolbarArea && !this._goodbyeClicked && !stillOpen) {
                            floatingButtons.style.display = 'none';
                        }
                        hideButtonsTimer = null;
                    }, 1000);
                }
            }
        });

        // PIXI 内部的鼠标跟踪（用于模型视线）
        this.pixi_app.stage.on('pointermove', (event) => {
            const lockIcon = document.getElementById('live2d-lock-icon');
            const pointer = event.data.global;
            
            // 在拖拽期间不执行任何操作
            if (model.interactive && model.dragging) {
                this.isFocusing = false;
                if (lockIcon) lockIcon.style.display = 'none';
                return;
            }
            
            // 如果已经点击了"请她离开"，永远不显示浮动按钮和锁按钮
            if (this._goodbyeClicked) {
                if (lockIcon) {
                    lockIcon.style.setProperty('display', 'none', 'important');
                }
                return;
            }

            const bounds = model.getBounds();
            const dx = Math.max(bounds.left - pointer.x, 0, pointer.x - bounds.right);
            const dy = Math.max(bounds.top - pointer.y, 0, pointer.y - bounds.bottom);
            const distance = Math.sqrt(dx * dx + dy * dy);

            if (distance < threshold) {
                this.isFocusing = true;
                if (lockIcon) lockIcon.style.display = 'block';
            } else {
                this.isFocusing = false;
                if (lockIcon) lockIcon.style.display = 'none';
            }

            if (this.isFocusing && this.mouseTrackingEnabled) {
                model.focus(pointer.x, pointer.y);
            } else if (!this.mouseTrackingEnabled && this.currentModel) {
                // 如果眼神跟随关闭，确保视线归零（或者保持上一次的 lookAt）
                // 这里我们不强制归零，因为可能正在执行 Motion Agent 的 lookAt 指令
                // 只有当用户明确想要"重置"时才归零，或者由 Motion Agent 控制
            }
        });
    }

    // 获取模型能力（动作和表情列表）
    getModelCapabilities() {
        const caps = {
            motions: [],
            expressions: []
        };
        
        if (this.emotionMapping) {
            if (this.emotionMapping.motions) {
                caps.motions = Object.keys(this.emotionMapping.motions);
            }
            if (this.emotionMapping.expressions) {
                caps.expressions = Object.keys(this.emotionMapping.expressions);
            }
        }
        
        // 如果没有映射，尝试从 FileReferences 推导
        if ((caps.motions.length === 0 || caps.expressions.length === 0) && this.fileReferences) {
            const derived = this.deriveEmotionMappingFromFileRefs(this.fileReferences);
            if (caps.motions.length === 0) caps.motions = Object.keys(derived.motions);
            if (caps.expressions.length === 0) caps.expressions = Object.keys(derived.expressions);
        }
        
        return caps;
    }

    // 主动控制视线（当眼神跟随关闭时使用）
    lookAt(x, y) {
        if (this.mouseTrackingEnabled) {
            console.warn('眼神跟随已开启，lookAt 可能被覆盖');
        }
        if (this.currentModel) {
            this.currentModel.focus(x, y);
        }
    }

    // 应用参数控制
    applyParameters(params, silent = false) {
        if (!this.currentModel || !this.currentModel.internalModel || !this.currentModel.internalModel.coreModel) return;
        
        if (!silent) {
            console.log('[Motion Agent] Applying parameters:', params);
            if (typeof logToScreen === 'function') {
                logToScreen(`[Motion] Applying ${Object.keys(params).length} params: ${JSON.stringify(params)}`);
            }
        }

        // Ensure overrides object exists
        if (!this.parameterOverrides) this.parameterOverrides = {};
        if (!this.overriddenIndices) this.overriddenIndices = {}; // Cache for indices

        const core = this.currentModel.internalModel.coreModel;

        // Update overrides
        Object.keys(params).forEach(key => {
            const value = params[key];
            // If value is null, remove from overrides (release control)
            if (value === null) {
                delete this.parameterOverrides[key];
                
                // Also remove from index cache
                if (core.getParameterIndex) {
                    const idx = core.getParameterIndex(key);
                    if (idx !== -1) delete this.overriddenIndices[idx];
                }

                if (typeof logToScreen === 'function') logToScreen(`[Motion] Released param: ${key}`);
            } else {
                this.parameterOverrides[key] = value;
                
                // Cache index
                if (core.getParameterIndex) {
                    const idx = core.getParameterIndex(key);
                    if (idx !== -1) this.overriddenIndices[idx] = value;
                }

                // Also set immediately for responsiveness
                try {
                    core.setParameterValueById(key, value);
                } catch (e) {
                    console.warn(`[Motion] Failed to set param ${key} immediately:`, e);
                }
            }
        });
    }

    // Smoothly release parameters to their internal values (avoids snapping)
    async releaseParametersSmoothly(keys, duration = 500) {
        if (!keys || keys.length === 0) return;
        
        return new Promise(resolve => {
            const startValues = {};
            keys.forEach(key => {
                // If override exists, use it as start. Else use internal or 0.
                if (this.parameterOverrides && this.parameterOverrides[key] !== undefined) {
                    startValues[key] = this.parameterOverrides[key];
                } else {
                    // If no override, we are already released, so skip
                    startValues[key] = null;
                }
            });
            
            // Filter out keys that don't need smoothing
            const activeKeys = keys.filter(k => startValues[k] !== null);
            if (activeKeys.length === 0) {
                resolve();
                return;
            }
            
            const startTime = performance.now();
            const animate = (currentTime) => {
                const elapsed = currentTime - startTime;
                const progress = Math.min(elapsed / duration, 1);
                // Ease out cubic
                const eased = 1 - Math.pow(1 - progress, 3);
                
                const frameParams = {};
                let stillRunning = false;
                
                activeKeys.forEach(key => {
                    const start = startValues[key];
                    // Target is dynamic!
                    const target = (this.internalParameterValues && this.internalParameterValues[key]) !== undefined 
                        ? this.internalParameterValues[key] 
                        : 0;
                    
                    if (progress < 1) {
                        const val = start + (target - start) * eased;
                        frameParams[key] = val;
                        stillRunning = true;
                    } else {
                        frameParams[key] = null; // Release final
                    }
                });
                
                this.applyParameters(frameParams, true);
                
                if (stillRunning) {
                    requestAnimationFrame(animate);
                } else {
                    resolve();
                }
            };
            requestAnimationFrame(animate);
        });
    }

    // 请求后端 Motion Agent 决策动作
    async askMotionAgent(userText, aiText, config = {}) {
        if (!this.currentModel) return;
        
        const capabilities = this.getModelCapabilities();
        const currentEmotion = this.currentEmotion || 'neutral';
        
        console.log('[Motion Agent] Requesting decision...', { userText, aiText, emotion: currentEmotion, config });

        const headers = {
            'Content-Type': 'application/json'
        };

        if (config.apiKey) headers['X-Motion-Api-Key'] = config.apiKey;
        if (config.baseUrl) headers['X-Motion-Base-Url'] = config.baseUrl;
        if (config.model) headers['X-Motion-Model'] = config.model;

        try {
            const response = await fetch('/api/live2d/agent/decide', {
                method: 'POST',
                headers: headers,
                body: JSON.stringify({
                    user_text: userText,
                    ai_text: aiText,
                    emotion: currentEmotion,
                    capabilities: capabilities,
                    history: config.history
                })
            });
            
            if (!response.ok) {
                throw new Error(`Motion Agent API error: ${response.status}`);
            }
            
            const decision = await response.json();
            console.log('[Motion Agent] Decision:', decision);
            
            // 执行决策
            if (decision.expression) {
                console.log(`[Motion Agent] Playing expression: ${decision.expression}`);
                this.playExpression(decision.expression);
            }

            if (decision.motion) {
                console.log(`[Motion Agent] Playing motion: ${decision.motion}`);
                this.playMotion(decision.motion);
            }
            
            if (decision.look_at) {
                console.log(`[Motion Agent] Looking at: ${decision.look_at.x}, ${decision.look_at.y}`);
                this.lookAt(decision.look_at.x, decision.look_at.y);
            } else if (!this.mouseTrackingEnabled) {
                // 如果没有特定视线指令且眼神跟随关闭，看回中心
                this.lookAt(0, 0);
            }

            // 执行参数控制
            if (decision.parameters) {
                console.log('[Motion Agent] Applying parameters (Smooth):', decision.parameters);
                // Use smooth interpolation for all parameter changes
                this.tweenParameters(decision.parameters, 500, t => 1 - Math.pow(1 - t, 3));
            }
            
            return decision;
            
        } catch (error) {
            console.error('[Motion Agent] Failed:', error);
        }
    }

    // 获取当前模型
    getCurrentModel() {
        return this.currentModel;
    }

    // 获取当前情感映射
    getEmotionMapping() {
        return this.emotionMapping;
    }

    // 获取 PIXI 应用
    getPIXIApp() {
        return this.pixi_app;
    }
}

// 同步服务器端的情绪映射（可仅替换“常驻”表情组）
Live2DManager.prototype.syncEmotionMappingWithServer = async function(options = {}) {
    const { replacePersistentOnly = true } = options;
    try {
        if (!this.modelName) return;
        const resp = await fetch(`/api/live2d/emotion_mapping/${encodeURIComponent(this.modelName)}`);
        if (!resp.ok) return;
        const data = await resp.json();
        if (!data || !data.success || !data.config) return;

        const serverMapping = data.config || { motions: {}, expressions: {} };
        if (!this.emotionMapping) this.emotionMapping = { motions: {}, expressions: {} };
        if (!this.emotionMapping.expressions) this.emotionMapping.expressions = {};

        if (replacePersistentOnly) {
            if (serverMapping.expressions && Array.isArray(serverMapping.expressions['常驻'])) {
                this.emotionMapping.expressions['常驻'] = [...serverMapping.expressions['常驻']];
            }
        } else {
            this.emotionMapping = serverMapping;
        }
    } catch (_) {
        // 静默失败，保持现有映射
    }
};

// ========== 常驻表情：实现 ==========
Live2DManager.prototype.collectPersistentExpressionFiles = function() {
    // 1) EmotionMapping.expressions.常驻
    const filesFromMapping = (this.emotionMapping && this.emotionMapping.expressions && this.emotionMapping.expressions['常驻']) || [];

    // 2) 兼容：从 FileReferences.Expressions 里按前缀 "常驻_" 推导
    let filesFromRefs = [];
    if ((!filesFromMapping || filesFromMapping.length === 0) && this.fileReferences && Array.isArray(this.fileReferences.Expressions)) {
        filesFromRefs = this.fileReferences.Expressions
            .filter(e => (e.Name || '').startsWith('常驻_'))
            .map(e => e.File)
            .filter(Boolean);
    }

    const all = [...filesFromMapping, ...filesFromRefs];
    // 去重
    return Array.from(new Set(all));
};

Live2DManager.prototype.setupPersistentExpressions = async function() {
    try {
        this.persistentExpressionNames = [];
        this.persistentExpressionParamsByName = {};
        const files = this.collectPersistentExpressionFiles();
        if (!files || files.length === 0) {
            this.teardownPersistentExpressions();
            console.log('未配置常驻表情');
            return;
        }

        for (const file of files) {
            try {
                const url = this.resolveAssetPath(file);
                const resp = await fetch(url);
                if (!resp.ok) continue;
                const data = await resp.json();
                const params = Array.isArray(data.Parameters) ? data.Parameters : [];
                const base = String(file).split('/').pop() || '';
                const name = base.replace('.exp3.json', '');
                // 只有包含参数的表达才加入播放队列
                if (params.length > 0) {
                    this.persistentExpressionNames.push(name);
                    this.persistentExpressionParamsByName[name] = params;
                }
            } catch (e) {
                console.warn('加载常驻表情失败:', file, e);
            }
        }

        // 使用官方 expression API 依次播放一次（若支持），并记录名称
        await this.applyPersistentExpressionsNative();
        console.log('常驻表情已启用，数量:', this.persistentExpressionNames.length);
    } catch (e) {
        console.warn('设置常驻表情失败:', e);
    }
};

Live2DManager.prototype.teardownPersistentExpressions = function() {
    this.persistentExpressionNames = [];
    this.persistentExpressionParamsByName = {};
};

Live2DManager.prototype.applyPersistentExpressionsNative = async function() {
    if (!this.currentModel) return;
    if (typeof this.currentModel.expression !== 'function') return;
    for (const name of this.persistentExpressionNames || []) {
        try {
            const maybe = await this.currentModel.expression(name);
            if (!maybe && this.persistentExpressionParamsByName && Array.isArray(this.persistentExpressionParamsByName[name])) {
                // 回退：手动设置参数
                try {
                    const params = this.persistentExpressionParamsByName[name];
                    const core = this.currentModel.internalModel && this.currentModel.internalModel.coreModel;
                    if (core) {
                        for (const p of params) {
                            try { core.setParameterValueById(p.Id, p.Value); } catch (_) {}
                        }
                    }
                } catch (_) {}
            }
        } catch (e) {
            // 名称可能未注册，尝试回退到手动设置
            try {
                if (this.persistentExpressionParamsByName && Array.isArray(this.persistentExpressionParamsByName[name])) {
                    const params = this.persistentExpressionParamsByName[name];
                    const core = this.currentModel.internalModel && this.currentModel.internalModel.coreModel;
                    if (core) {
                        for (const p of params) {
                            try { core.setParameterValueById(p.Id, p.Value); } catch (_) {}
                        }
                    }
                }
            } catch (_) {}
        }
    }
};

// 创建全局 Live2D 管理器实例
window.Live2DManager = Live2DManager;
window.live2dManager = new Live2DManager();

// 兼容性：保持原有的全局变量和函数
window.LanLan1 = window.LanLan1 || {};
window.LanLan1.setEmotion = (emotion) => window.live2dManager.setEmotion(emotion);
window.LanLan1.playExpression = (emotion) => window.live2dManager.playExpression(emotion);
window.LanLan1.playMotion = (emotion) => window.live2dManager.playMotion(emotion);
window.LanLan1.clearEmotionEffects = () => window.live2dManager.clearEmotionEffects();
window.LanLan1.clearExpression = () => window.live2dManager.clearExpression();
window.LanLan1.setMouth = (value) => window.live2dManager.setMouth(value);
window.LanLan1.lookAt = (x, y) => window.live2dManager.lookAt(x, y);
window.LanLan1.askMotionAgent = (u, a) => window.live2dManager.askMotionAgent(u, a);
window.LanLan1.getModelCapabilities = () => window.live2dManager.getModelCapabilities();

// 自动初始化（如果存在 cubism4Model 变量）
if (typeof cubism4Model !== 'undefined' && cubism4Model) {
    (async function() {
        try {
            // 初始化 PIXI 应用
            await window.live2dManager.initPIXI('live2d-canvas', 'live2d-container');
            
            // 加载用户偏好
            const preferences = await window.live2dManager.loadUserPreferences();
            
            // 根据模型路径找到对应的偏好设置
            let modelPreferences = null;
            if (preferences && preferences.length > 0) {
                modelPreferences = preferences.find(p => p && p.model_path === cubism4Model);
                if (modelPreferences) {
                    console.log('找到模型偏好设置:', modelPreferences);
                } else {
                    console.log('未找到模型偏好设置，将使用默认设置');
                }
            }
            
            // 加载模型
            await window.live2dManager.loadModel(cubism4Model, {
                preferences: modelPreferences,
                isMobile: window.innerWidth <= 768
            });

            // 设置全局引用（兼容性）
            window.LanLan1.live2dModel = window.live2dManager.getCurrentModel();
            window.LanLan1.currentModel = window.live2dManager.getCurrentModel();
            window.LanLan1.emotionMapping = window.live2dManager.getEmotionMapping();

            // 等待几帧后根据模型位置动态设置文本框初始位置
            setTimeout(() => {
                try {
                    const model = window.live2dManager.getCurrentModel();
                    const chatContainer = document.getElementById('chat-container');
                    
                    if (model && chatContainer && window.innerWidth > 768) {
                        // 只在桌面端调整，移动端使用响应式CSS
                        const bounds = model.getBounds();
                        const screenWidth = window.innerWidth;
                        const screenHeight = window.innerHeight;
                        
                        // 计算锁按钮的位置（与setupLockIcon中的逻辑一致）
                        const lockX = bounds.right * 0.7 + bounds.left * 0.3;
                        const lockY = bounds.top * 0.3 + bounds.bottom * 0.7;
                        
                        // 文本框位置：在模型左侧，比锁按钮稍低一些
                        // left: 在锁按钮左侧偏移一点，但不要太靠左
                        const chatLeft = Math.max(20, bounds.left - 400);
                        // bottom: 比锁按钮低60px左右
                        const chatBottom = Math.max(20, screenHeight - lockY - 200);
                        
                        chatContainer.style.left = `${chatLeft}px`;
                        chatContainer.style.bottom = `${chatBottom}px`;
                        
                        console.log('文本框位置已根据模型位置调整:', {chatLeft, chatBottom, lockX, lockY});
                    }
                } catch (error) {
                    console.warn('调整文本框位置失败:', error);
                }
            }, 500);

            console.log('Live2D 管理器自动初始化完成');
        } catch (error) {
            console.error('Live2D 管理器自动初始化失败:', error);
        }
    })();
}
