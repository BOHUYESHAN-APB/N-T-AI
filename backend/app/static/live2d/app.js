function init_app(){
    const micButton = document.getElementById('micButton');
    const muteButton = document.getElementById('muteButton');
    const screenButton = document.getElementById('screenButton');
    const stopButton = document.getElementById('stopButton');
    const resetSessionButton = document.getElementById('resetSessionButton');
    const statusElement = document.getElementById('status');
    const chatContainer = document.getElementById('chatContainer');
    const textInputBox = document.getElementById('textInputBox');
    const textSendButton = document.getElementById('textSendButton');
    const screenshotButton = document.getElementById('screenshotButton');
    const screenshotThumbnailContainer = document.getElementById('screenshot-thumbnail-container');
    const screenshotsList = document.getElementById('screenshots-list');
    const screenshotCount = document.getElementById('screenshot-count');
    const clearAllScreenshots = document.getElementById('clear-all-screenshots');

    let audioContext;
    let workletNode;
    let stream;
    let isRecording = false;
    let socket;
    let currentGeminiMessage = null;
    let audioPlayerContext = null;
    let videoTrack, videoSenderInterval;
    let audioBufferQueue = [];
    let screenshotCounter = 0; // 截图计数器
    let isPlaying = false;
    let audioStartTime = 0;
    let scheduledSources = [];
    let animationFrameId;
    let seqCounter = 0;
    let globalAnalyser = null;
    let lipSyncActive = false;
    let screenCaptureStream = null; // 暂存屏幕共享stream，不再需要每次都弹窗选择共享区域，方便自动重连
    // 新增：当前选择的麦克风设备ID
    let selectedMicrophoneId = null;
    
    // 麦克风静音检测相关变量
    let silenceDetectionTimer = null;
    let hasSoundDetected = false;
    let inputAnalyser = null;
    
    // 模式管理
    let isTextSessionActive = false;
    let isSwitchingMode = false; // 新增：模式切换标志
    let sessionStartedResolver = null; // 用于等待 session_started 消息
    
    // 主动搭话功能相关
    let proactiveChatEnabled = false;
    let proactiveChatTimer = null;
    let proactiveChatBackoffLevel = 0; // 退避级别：0=30s, 1=1min, 2=2min, 3=4min, etc.
    const PROACTIVE_CHAT_BASE_DELAY = 30000; // 30秒基础延迟
    
    // Focus模式相关（兼容原有的focus_mode）
    let focusModeEnabled = (typeof focus_mode !== 'undefined' && focus_mode === true) ? true : false;
    
    // 暴露到全局作用域，供 live2d.js 等其他模块访问
    window.proactiveChatEnabled = proactiveChatEnabled;
    window.focusModeEnabled = focusModeEnabled;
    
    // WebSocket心跳保活
    let heartbeatInterval = null;
    const HEARTBEAT_INTERVAL = 30000; // 30秒发送一次心跳

    function isMobile() {
      return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(
        navigator.userAgent
      );
    }

    // 建立WebSocket连接
    function connectWebSocket() {
        const protocol = window.location.protocol === "https:" ? "wss" : "ws";
        // [Refactor] Use 'default_user' or config name, fallback to 'Firefly' if undefined
        // Original: lanlan_config.lanlan_name
        const characterName = (typeof lanlan_config !== 'undefined' && lanlan_config.lanlan_name) ? lanlan_config.lanlan_name : 'Firefly';
        socket = new WebSocket(`${protocol}://${window.location.host}/ws/${characterName}`);

        socket.onopen = () => {
            console.log('WebSocket连接已建立');
            
            // 启动心跳保活机制
            if (heartbeatInterval) {
                clearInterval(heartbeatInterval);
            }
            heartbeatInterval = setInterval(() => {
                if (socket.readyState === WebSocket.OPEN) {
                    socket.send(JSON.stringify({
                        action: 'ping'
                    }));
                }
            }, HEARTBEAT_INTERVAL);
            console.log('心跳保活机制已启动');
        };

        socket.onmessage = (event) => {
            if (event.data instanceof Blob) {
                // 处理二进制音频数据
                console.log("收到新的音频块")
                handleAudioBlob(event.data);
                return;
            }

            try {
                const response = JSON.parse(event.data);


                if (response.type === 'gemini_response') {
                    // 检查是否是新消息的开始
                    const isNewMessage = response.isNewMessage || false;
                    appendMessage(response.text, 'gemini', isNewMessage);
                } else if (response.type === 'user_transcript') {
                    // 处理用户语音转录，显示在聊天界面
                    appendMessage(response.text, 'user', true);
                } else if (response.type === 'user_activity') {
                    clearAudioQueue();
                } if (response.type === 'cozy_audio') {
                    // 处理音频响应
                    console.log("收到新的音频头")
                    const isNewMessage = response.isNewMessage || false;

                    if (isNewMessage) {
                        // 如果是新消息，清空当前音频队列
                        clearAudioQueue();
                    }

                    // 根据数据格式选择处理方法
                    if (response.format === 'base64') {
                        handleBase64Audio(response.audioData, isNewMessage);
                    }
                } else if (response.type === 'screen_share_error') {
                    // 屏幕分享/截图错误，复位按钮状态
                    statusElement.textContent = response.message;
                    
                    // 停止屏幕分享
                    stopScreening();
                    
                    // 清理屏幕捕获流
                    if (screenCaptureStream) {
                        screenCaptureStream.getTracks().forEach(track => track.stop());
                        screenCaptureStream = null;
                    }
                    
                    // 复位按钮状态
                    if (isRecording) {
                        // 在语音模式下（屏幕分享）
                        micButton.disabled = true;
                        muteButton.disabled = false;
                        screenButton.disabled = false;
                        stopButton.disabled = true;
                        resetSessionButton.disabled = false;
                    } else if (isTextSessionActive) {
                        // 在文本模式下（截图）
                        screenshotButton.disabled = false;
                    }
                } else if (response.type === 'status') {
                    // 如果正在切换模式且收到"已离开"消息，则忽略
                    if (isSwitchingMode && response.message.includes('已离开')) {
                        console.log('模式切换中，忽略"已离开"状态消息');
                        return;
                    }
                    statusElement.textContent = response.message;
                    if (response.message === `${lanlan_config.lanlan_name}失联了，即将重启！`){
                        if (isRecording === false && !isTextSessionActive){
                            statusElement.textContent = `${lanlan_config.lanlan_name}正在打盹...`;
                        } else if (isTextSessionActive) {
                            statusElement.textContent = `正在文本聊天中...`;
                        } else {
                            stopRecording();
                            if (socket.readyState === WebSocket.OPEN) {
                                socket.send(JSON.stringify({
                                    action: 'end_session'
                                }));
                            }
                            hideLive2d();
                            micButton.disabled = true;
                            muteButton.disabled = true;
                            screenButton.disabled = true;
                            stopButton.disabled = true;
                            resetSessionButton.disabled = true;

                            setTimeout(async () => {
                                try {
                                    // 创建一个 Promise 来等待 session_started 消息
                                    const sessionStartPromise = new Promise((resolve, reject) => {
                                        sessionStartedResolver = resolve;
                                        
                                        // 设置超时（15秒），如果超时则拒绝
                                        setTimeout(() => {
                                            if (sessionStartedResolver) {
                                                sessionStartedResolver = null;
                                                reject(new Error('Session启动超时'));
                                            }
                                        }, 10000);
                                    });
                                    
                                    // 发送start session事件
                                    socket.send(JSON.stringify({
                                        action: 'start_session',
                                        input_type: 'audio'
                                    }));
                                    
                                    // 等待session真正启动成功
                                    await sessionStartPromise;
                                    
                                    showLive2d();
                                    await startMicCapture();
                                    if (screenCaptureStream != null){
                                        await startScreenSharing();
                                    }
                                    statusElement.textContent = `重启完成，${lanlan_config.lanlan_name}回来了！`;
                                } catch (error) {
                                    console.error("重启时出错:", error);
                                    statusElement.textContent = `重启失败: ${error.message}`;
                                }
                            }, 7500); // 7.5秒后执行
                        }
                    }
                } else if (response.type === 'expression') {
                    window.LanLan1.registered_expressions[response.message]();
                } else if (response.type === 'system' && response.data === 'turn end') {
                    console.log('收到turn end事件，开始情感分析');
                    // 消息完成时进行情感分析
                    if (currentGeminiMessage) {
                        const fullText = currentGeminiMessage.textContent.replace(/^\[\d{2}:\d{2}:\d{2}\] 🎀 /, '');
                        setTimeout(async () => {
                            const emotionResult = await analyzeEmotion(fullText);
                            if (emotionResult && emotionResult.emotion) {
                                console.log('消息完成，情感分析结果:', emotionResult);
                                applyEmotion(emotionResult.emotion);
                            }
                        }, 100);
                    }
                    
                    // AI回复完成后，重置主动搭话计时器（如果已开启且在文本模式）
                    if (proactiveChatEnabled && !isRecording) {
                        resetProactiveChatBackoff();
                    }
                } else if (response.type === 'session_started') {
                    console.log('收到session_started事件，模式:', response.input_mode);
                    // 解析 session_started Promise
                    if (sessionStartedResolver) {
                        sessionStartedResolver(response.input_mode);
                        sessionStartedResolver = null;
                    }
                } else if (response.type === 'auto_close_mic') {
                    console.log('收到auto_close_mic事件，自动关闭麦克风');
                    // 长时间无语音输入，自动关闭麦克风但不关闭live2d
                    if (isRecording) {
                        // 停止录音，但不隐藏live2d
                        stopRecording();
                        
                        // 复位按钮状态
                        micButton.disabled = false;
                        muteButton.disabled = true;
                        screenButton.disabled = true;
                        stopButton.disabled = true;
                        resetSessionButton.disabled = false;
                        
                        // 移除录音状态类
                        micButton.classList.remove('recording');
                        const toggleButton = document.getElementById('toggle-mic-selector');
                        if (toggleButton) {
                            toggleButton.classList.remove('recording');
                        }
                        
                        // 重置浮动按钮状态（恢复默认白色背景）
                        const floatingMicBtn = document.getElementById('live2d-btn-mic');
                        if (floatingMicBtn) {
                            floatingMicBtn.dataset.active = 'false';
                            floatingMicBtn.style.background = 'rgba(255, 255, 255, 0.9)';
                        }
                        const floatingScreenBtn = document.getElementById('live2d-btn-screen');
                        if (floatingScreenBtn) {
                            floatingScreenBtn.dataset.active = 'false';
                            floatingScreenBtn.style.background = 'rgba(255, 255, 255, 0.9)';
                        }
                        
                        // 显示提示信息
                        statusElement.textContent = response.message || '长时间无语音输入，已自动关闭麦克风';
                    }
                }
            } catch (error) {
                console.error('处理消息失败:', error);
            }
        };

        socket.onclose = () => {
            console.log('WebSocket连接已关闭');
            
            // 清理心跳定时器
            if (heartbeatInterval) {
                clearInterval(heartbeatInterval);
                heartbeatInterval = null;
                console.log('心跳保活机制已停止');
            }
            
            // 重置文本session状态，因为后端会清理session
            if (isTextSessionActive) {
                isTextSessionActive = false;
                console.log('WebSocket断开，已重置文本session状态');
            }
            // 尝试重新连接
            setTimeout(connectWebSocket, 3000);
        };

        socket.onerror = (error) => {
            console.error('WebSocket错误:', error);
        };
    }

    // 初始化连接
    connectWebSocket();

    // 添加消息到聊天界面
    function appendMessage(text, sender, isNewMessage = true) {
        function getCurrentTimeString() {
            return new Date().toLocaleTimeString('en-US', {
                hour12: false,
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
        }

        if (sender === 'gemini' && !isNewMessage && currentGeminiMessage) {
            // 追加到现有的Gemini消息
            // currentGeminiMessage.textContent += text;
            currentGeminiMessage.insertAdjacentHTML('beforeend', text.replaceAll('\n', '<br>'));
        } else {
            // 创建新消息
            const messageDiv = document.createElement('div');
            messageDiv.classList.add('message', sender);
            
            // 根据sender设置不同的图标
            const icon = sender === 'user' ? '💬' : '🎀';
            messageDiv.textContent = "[" + getCurrentTimeString() + "] " + icon + " " + text;
            chatContainer.appendChild(messageDiv);

            // 如果是Gemini消息，更新当前消息引用
            if (sender === 'gemini') {
                currentGeminiMessage = messageDiv;
            }
        }
        chatContainer.scrollTop = chatContainer.scrollHeight;
    }


        // 全局变量用于缓存麦克风列表和缓存时间戳
    let cachedMicrophones = null;
    let cacheTimestamp = 0;
    const CACHE_DURATION = 30000; // 缓存30秒

    // 麦克风选择器UI已迁移到浮动按钮系统（live2d.js），保留核心函数供其使用
    
    // 选择麦克风
    async function selectMicrophone(deviceId) {
        selectedMicrophoneId = deviceId;
        
        // 更新UI选中状态
        const options = document.querySelectorAll('.mic-option');
        options.forEach(option => {
            if ((option.classList.contains('default') && deviceId === null) || 
                (option.dataset.deviceId === deviceId && deviceId !== null)) {
                option.classList.add('selected');
            } else {
                option.classList.remove('selected');
            }
        });
        
        // 保存选择到服务器
        await saveSelectedMicrophone(deviceId);
        
        // 如果正在录音，重启录音以使用新选择的麦克风
        if (isRecording) {
            const wasRecording = isRecording;
            await stopMicCapture();
            if (wasRecording) {
                await startMicCapture();
            }
        }
    }
    
    // 保存选择的麦克风到服务器
    async function saveSelectedMicrophone(deviceId) {
        try {
            const response = await fetch('/api/characters/set_microphone', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    microphone_id: deviceId
                })
            });
            
            if (!response.ok) {
                console.error('保存麦克风选择失败');
            }
        } catch (err) {
            console.error('保存麦克风选择时发生错误:', err);
        }
    }
    
    // 加载上次选择的麦克风
    async function loadSelectedMicrophone() {
        try {
            const response = await fetch('/api/characters/get_microphone');
            if (response.ok) {
                const data = await response.json();
                selectedMicrophoneId = data.microphone_id || null;
            }
        } catch (err) {
            console.error('加载麦克风选择失败:', err);
            selectedMicrophoneId = null;
        }
    }
    
    // 开麦，按钮on click
    async function startMicCapture() {
        try {
            // 开始录音前添加录音状态类到两个按钮
            micButton.classList.add('recording');
            // 同步更新麦克风选择器按钮样式
            const toggleButton = document.getElementById('toggle-mic-selector');
            if (toggleButton) {
                toggleButton.classList.add('recording');
            }
            
            // 同步更新浮动麦克风按钮状态（设置为激活状态，蓝色高亮）
            const floatingMicBtn = document.getElementById('live2d-btn-mic');
            if (floatingMicBtn) {
                floatingMicBtn.dataset.active = 'true';
                floatingMicBtn.style.background = 'rgba(79, 140, 255, 0.9)';
            }
            
            if (!audioPlayerContext) {
                audioPlayerContext = new (window.AudioContext || window.webkitAudioContext)();
            }

            if (audioPlayerContext.state === 'suspended') {
                await audioPlayerContext.resume();
            }

            // 获取麦克风流，使用选择的麦克风设备ID
            const constraints = {
                audio: selectedMicrophoneId ? { deviceId: { exact: selectedMicrophoneId } } : true
            };
            
            stream = await navigator.mediaDevices.getUserMedia(constraints);

            // 检查音频轨道状态
            const audioTracks = stream.getAudioTracks();
            console.log("音频轨道数量:", audioTracks.length);
            console.log("音频轨道状态:", audioTracks.map(track => ({
                label: track.label,
                enabled: track.enabled,
                muted: track.muted,
                readyState: track.readyState
            })));

            if (audioTracks.length === 0) {
                console.error("没有可用的音频轨道");
                statusElement.textContent = '无法访问麦克风';
                return;
            }

            await startAudioWorklet(stream);

            micButton.disabled = true;
            muteButton.disabled = false;
            screenButton.disabled = false;
            stopButton.disabled = true;
            resetSessionButton.disabled = false;
            statusElement.textContent = '正在语音...';
            
            // 开始录音时，停止主动搭话定时器
            stopProactiveChatSchedule();
        } catch (err) {
            console.error('获取麦克风权限失败:', err);
            statusElement.textContent = '无法访问麦克风';
            // 失败时移除两个按钮的录音状态类
            micButton.classList.remove('recording');
            const toggleButton = document.getElementById('toggle-mic-selector');
            if (toggleButton) {
                toggleButton.classList.remove('recording');
            }
            // 失败时也重置浮动麦克风按钮状态
            const floatingMicBtn = document.getElementById('live2d-btn-mic');
            if (floatingMicBtn) {
                floatingMicBtn.dataset.active = 'false';
                floatingMicBtn.style.background = 'rgba(255, 255, 255, 0.9)';
            }
        }
    }

    async function stopMicCapture(){ // 闭麦，按钮on click
        isSwitchingMode = true; // 开始模式切换（从语音切换到待机/文本模式）
        
        // 停止录音时移除两个按钮的录音状态类
        micButton.classList.remove('recording');
        const toggleButton = document.getElementById('toggle-mic-selector');
        if (toggleButton) {
            toggleButton.classList.remove('recording');
        }
        
        // 同步重置浮动麦克风按钮状态
        const floatingMicBtn = document.getElementById('live2d-btn-mic');
        if (floatingMicBtn) {
            floatingMicBtn.dataset.active = 'false';
            floatingMicBtn.style.background = 'rgba(255, 255, 255, 0.9)';
        }
        
        stopRecording();
        micButton.disabled = false;
        muteButton.disabled = true;
        screenButton.disabled = true;
        stopButton.disabled = true;
        resetSessionButton.disabled = false;
        
        // 停止录音后，重置主动搭话退避级别并开始定时
        if (proactiveChatEnabled) {
            resetProactiveChatBackoff();
        }
        
        // 显示文本输入区
        const textInputArea = document.getElementById('text-input-area');
        textInputArea.classList.remove('hidden');
        
        // 如果是从语音模式切换回来，显示待机状态
        // [Refactor] Use 'Firefly' as default name
        const characterName = (typeof lanlan_config !== 'undefined' && lanlan_config.lanlan_name) ? lanlan_config.lanlan_name : 'Firefly';
        statusElement.textContent = `${characterName}待机中...`;
        
        // 延迟重置模式切换标志，确保"已离开"消息已经被忽略
        setTimeout(() => {
            isSwitchingMode = false;
        }, 500);
    }

    async function getMobileCameraStream() {
      const makeConstraints = (facing) => ({
        video: {
          facingMode: facing,
          frameRate: { ideal: 1, max: 1 },
        },
        audio: false,
      });

      const attempts = [
        { label: 'rear', constraints: makeConstraints({ ideal: 'environment' }) },
        { label: 'front', constraints: makeConstraints('user') },
        { label: 'any', constraints: { video: { frameRate: { ideal: 1, max: 1 } }, audio: false } },
      ];

      let lastError;

      for (const attempt of attempts) {
        try {
          console.log(`Trying ${attempt.label} camera @ ${1}fps…`);
          return await navigator.mediaDevices.getUserMedia(attempt.constraints);
        } catch (err) {
          console.warn(`${attempt.label} failed →`, err);
          statusElement.textContent = err;
          return err;
        }
      }
    }

    async function startScreenSharing(){ // 分享屏幕，按钮on click
        // 检查是否在录音状态
        if (!isRecording) {
            statusElement.textContent = '请先开启麦克风录音！';
            return;
        }
        
        try {
            // 初始化音频播放上下文
            showLive2d();
            if (!audioPlayerContext) {
                audioPlayerContext = new (window.AudioContext || window.webkitAudioContext)();
            }

            // 如果上下文被暂停，则恢复它
            if (audioPlayerContext.state === 'suspended') {
                await audioPlayerContext.resume();
            }
            let captureStream;

            if (screenCaptureStream == null){
                if (isMobile()) {
                // On mobile we capture the *camera* instead of the screen.
                // `environment` is the rear camera (iOS + many Androids). If that's not
                // available the UA will fall back to any camera it has.
                screenCaptureStream = await getMobileCameraStream();

                } else {
                // Desktop/laptop: capture the user's chosen screen / window / tab.
                screenCaptureStream = await navigator.mediaDevices.getDisplayMedia({
                    video: {
                    cursor: 'always',
                    frameRate: 1,
                    },
                    audio: false,
                });
                }
            }
            startScreenVideoStreaming(screenCaptureStream, isMobile() ? 'camera' : 'screen');

            micButton.disabled = true;
            muteButton.disabled = false;
            screenButton.disabled = true;
            stopButton.disabled = false;
            resetSessionButton.disabled = false;

            // 当用户停止共享屏幕时
            screenCaptureStream.getVideoTracks()[0].onended = stopScreening;

            // 获取麦克风流
            if (!isRecording) statusElement.textContent = '没开麦啊喂！';
          } catch (err) {
            console.error(isMobile() ? '摄像头访问失败:' : '屏幕共享失败:', err);
            console.error('启动失败 →', err);
            let hint = '';
            switch (err.name) {
              case 'NotAllowedError':
                hint = '请检查 iOS 设置 → Safari → 摄像头 权限是否为"允许"';
                break;
              case 'NotFoundError':
                hint = '未检测到摄像头设备';
                break;
              case 'NotReadableError':
              case 'AbortError':
                hint = '摄像头被其它应用占用？关闭扫码/拍照应用后重试';
                break;
            }
            statusElement.textContent = `${err.name}: ${err.message}${hint ? `\n${hint}` : ''}`;
          }
    }

    async function stopScreenSharing(){ // 停止共享，按钮on click
        stopScreening();
        micButton.disabled = true;
        muteButton.disabled = false;
        screenButton.disabled = false;
        stopButton.disabled = true;
        resetSessionButton.disabled = false;
        screenCaptureStream = null;
        statusElement.textContent = '正在语音...';
    }

    window.switchMicCapture = async () => {
        if (muteButton.disabled) {
            await startMicCapture();
        } else {
            await stopMicCapture();
        }
    }
    window.switchScreenSharing = async () => {
        if (stopButton.disabled) {
            // 检查是否在录音状态
            if (!isRecording) {
                statusElement.textContent = '请先开启麦克风！';
                return;
            }
            await startScreenSharing();
        } else {
            await stopScreenSharing();
        }
    }

    // 显示语音准备提示框
    function showVoicePreparingToast(message) {
        // 检查是否已存在提示框，避免重复创建
        let toast = document.getElementById('voice-preparing-toast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'voice-preparing-toast';
            toast.style.cssText = `
                position: fixed;
                top: 50%;
                left: 50%;
                transform: translate(-50%, -50%);
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 20px 32px;
                border-radius: 16px;
                font-size: 16px;
                font-weight: 600;
                box-shadow: 0 8px 24px rgba(102, 126, 234, 0.5);
                z-index: 10000;
                display: flex;
                align-items: center;
                gap: 12px;
                animation: voiceToastFadeIn 0.3s ease;
                pointer-events: none;
            `;
            
            // 添加动画样式
            const style = document.createElement('style');
            style.textContent = `
                @keyframes voiceToastFadeIn {
                    from {
                        opacity: 0;
                        transform: translate(-50%, -50%) scale(0.8);
                    }
                    to {
                        opacity: 1;
                        transform: translate(-50%, -50%) scale(1);
                    }
                }
                @keyframes voiceToastPulse {
                    0%, 100% {
                        transform: scale(1);
                    }
                    50% {
                        transform: scale(1.1);
                    }
                }
            `;
            document.head.appendChild(style);
            
            document.body.appendChild(toast);
        }
        
        // 更新消息内容
        toast.innerHTML = `
            <div style="
                width: 20px;
                height: 20px;
                border: 3px solid rgba(255, 255, 255, 0.3);
                border-top-color: white;
                border-radius: 50%;
                animation: spin 1s linear infinite;
            "></div>
            <span>${message}</span>
        `;
        
        // 添加旋转动画
        const spinStyle = document.createElement('style');
        spinStyle.textContent = `
            @keyframes spin {
                to { transform: rotate(360deg); }
            }
        `;
        if (!document.querySelector('style[data-spin-animation]')) {
            spinStyle.setAttribute('data-spin-animation', 'true');
            document.head.appendChild(spinStyle);
        }
        
        toast.style.display = 'flex';
    }
    
    // 隐藏语音准备提示框
    function hideVoicePreparingToast() {
        const toast = document.getElementById('voice-preparing-toast');
        if (toast) {
            toast.style.animation = 'voiceToastFadeIn 0.3s ease reverse';
            setTimeout(() => {
                toast.style.display = 'none';
            }, 300);
        }
    }
    
    // 显示"可以说话了"提示
    function showReadyToSpeakToast() {
        let toast = document.getElementById('voice-ready-toast');
        if (!toast) {
            toast = document.createElement('div');
            toast.id = 'voice-ready-toast';
            toast.style.cssText = `
                position: fixed;
                top: 50%;
                left: 50%;
                transform: translate(-50%, -50%);
                background: linear-gradient(135deg, #28a745 0%, #20c997 100%);
                color: white;
                padding: 20px 32px;
                border-radius: 16px;
                font-size: 18px;
                font-weight: 600;
                box-shadow: 0 8px 24px rgba(40, 167, 69, 0.5);
                z-index: 10000;
                display: none;
                align-items: center;
                gap: 12px;
                animation: voiceToastFadeIn 0.3s ease;
                pointer-events: none;
            `;
            document.body.appendChild(toast);
        }
        
        toast.innerHTML = `
            <span style="font-size: 24px; animation: voiceToastPulse 0.6s ease;">🎤</span>
            <span>可以开始说话了！</span>
        `;
        
        toast.style.display = 'flex';
        
        // 2秒后自动消失
        setTimeout(() => {
            toast.style.animation = 'voiceToastFadeIn 0.3s ease reverse';
            setTimeout(() => {
                toast.style.display = 'none';
            }, 300);
        }, 2000);
    }

    // 开始麦克风录音
    micButton.addEventListener('click', async () => {
        // 立即显示准备提示
        showVoicePreparingToast('🎙️ 语音系统准备中...');
        
        // 如果有活跃的文本会话，先结束它
        if (isTextSessionActive) {
            isSwitchingMode = true; // 开始模式切换
            if (socket.readyState === WebSocket.OPEN) {
                socket.send(JSON.stringify({
                    action: 'end_session'
                }));
            }
            isTextSessionActive = false;
            statusElement.textContent = '正在切换到语音模式...';
            showVoicePreparingToast('🔄 正在切换到语音模式...');
            // 增加等待时间，确保后端完全清理资源
            await new Promise(resolve => setTimeout(resolve, 1500)); // 从500ms增加到1500ms
        }
        
        // 隐藏文本输入区
        const textInputArea = document.getElementById('text-input-area');
        textInputArea.classList.add('hidden');
        
        // 立即禁用所有语音按钮
        micButton.disabled = true;
        muteButton.disabled = true;
        screenButton.disabled = true;
        stopButton.disabled = true;
        resetSessionButton.disabled = true;
        
        statusElement.textContent = '正在初始化语音对话...';
        showVoicePreparingToast('⚙️ 正在连接服务器...');
        
        try {
            // 创建一个 Promise 来等待 session_started 消息
            const sessionStartPromise = new Promise((resolve, reject) => {
                sessionStartedResolver = resolve;
                
                // 设置超时（15秒），如果超时则拒绝
                setTimeout(() => {
                    if (sessionStartedResolver) {
                        sessionStartedResolver = null;
                        reject(new Error('Session启动超时'));
                    }
                }, 15000);
            });
            
            // 发送start session事件
            if (socket.readyState === WebSocket.OPEN) {
                socket.send(JSON.stringify({
                    action: 'start_session',
                    input_type: 'audio'
                }));
            } else {
                throw new Error('WebSocket未连接');
            }
            
            // 等待session真正启动成功
            await sessionStartPromise;
            
            statusElement.textContent = '正在初始化麦克风...';
            showVoicePreparingToast('🎤 正在初始化麦克风...');
            
            // 显示Live2D
            showLive2d();
            await startMicCapture();
            
            // 录音启动成功后，隐藏准备提示，显示"可以说话了"提示
            hideVoicePreparingToast();
            
            // 延迟1秒显示"可以说话了"提示，确保系统真正准备好
            setTimeout(() => {
                showReadyToSpeakToast();
            }, 1000);
            
            isSwitchingMode = false; // 模式切换完成
        } catch (error) {
            console.error('启动语音会话失败:', error);
            
            // 隐藏准备提示
            hideVoicePreparingToast();
            
            // 如果失败，恢复按钮状态和文本输入区
            micButton.disabled = false;
            muteButton.disabled = true;
            screenButton.disabled = true;
            stopButton.disabled = true;
            resetSessionButton.disabled = false;
            textInputArea.classList.remove('hidden');
            statusElement.textContent = `启动失败: ${error.message}`;
            isSwitchingMode = false; // 切换失败，重置标志
        }
    });

    // 开始屏幕共享
    screenButton.addEventListener('click', startScreenSharing);

    // 停止屏幕共享
    stopButton.addEventListener('click', stopScreenSharing);

    // 停止对话
    muteButton.addEventListener('click', stopMicCapture);

    resetSessionButton.addEventListener('click', () => {
        isSwitchingMode = true; // 开始重置会话（也是一种模式切换）
        
        // 检查是否是"请她离开"触发的
        const isGoodbyeMode = window.live2d && window.live2d._goodbyeClicked;
        
        hideLive2d()
        if (socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify({
                action: 'end_session'
            }));
        }
        stopRecording();
        clearAudioQueue();
        
        // 重置所有状态
        isTextSessionActive = false;
        
        // 清除所有截图
        screenshotsList.innerHTML = '';
        screenshotThumbnailContainer.classList.remove('show');
        updateScreenshotCount();
        screenshotCounter = 0;
        
        // 如果不是"请她离开"模式，才显示文本输入区并启用按钮
        if (!isGoodbyeMode) {
            // 结束会话后，重置主动搭话计时器（如果已开启）
            if (proactiveChatEnabled) {
                resetProactiveChatBackoff();
            }
            // 显示文本输入区
            const textInputArea = document.getElementById('text-input-area');
            textInputArea.classList.remove('hidden');
            
            // 启用所有输入
            micButton.disabled = false;
            textSendButton.disabled = false;
            textInputBox.disabled = false;
            screenshotButton.disabled = false;
            
            // 禁用语音控制按钮
            muteButton.disabled = true;
            screenButton.disabled = true;
            stopButton.disabled = true;
            resetSessionButton.disabled = true;
            
            statusElement.textContent = '会话已结束';
        } else {
            // "请她离开"模式：隐藏所有内容
            const textInputArea = document.getElementById('text-input-area');
            textInputArea.classList.add('hidden');
            
            // 禁用所有按钮
            micButton.disabled = true;
            textSendButton.disabled = true;
            textInputBox.disabled = true;
            screenshotButton.disabled = true;
            muteButton.disabled = true;
            screenButton.disabled = true;
            stopButton.disabled = true;
            resetSessionButton.disabled = true;
            
            statusElement.textContent = '';
        }
        
        // 延迟重置模式切换标志，确保"已离开"消息已经被忽略
        setTimeout(() => {
            isSwitchingMode = false;
        }, 500);
    });
    
    // 文本发送按钮事件
    textSendButton.addEventListener('click', async () => {
        const text = textInputBox.value.trim();
        const hasScreenshots = screenshotsList.children.length > 0;
        
        // 如果既没有文本也没有截图，静默返回
        if (!text && !hasScreenshots) {
            return;
        }
        
        // 如果还没有启动session，先启动
        if (!isTextSessionActive) {
            // 临时禁用文本输入
            textSendButton.disabled = true;
            textInputBox.disabled = true;
            screenshotButton.disabled = true;
            resetSessionButton.disabled = false;
            
            statusElement.textContent = '正在初始化文本对话...';
            
            try {
                // 创建一个 Promise 来等待 session_started 消息
                const sessionStartPromise = new Promise((resolve, reject) => {
                    sessionStartedResolver = resolve;
                    
                    // 设置超时（15秒），如果超时则拒绝
                    setTimeout(() => {
                        if (sessionStartedResolver) {
                            sessionStartedResolver = null;
                            reject(new Error('Session启动超时'));
                        }
                    }, 15000);
                });
                
                // 启动文本session
                if (socket.readyState === WebSocket.OPEN) {
                    socket.send(JSON.stringify({
                        action: 'start_session',
                        input_type: 'text',
                        new_session: false
                    }));
                } else {
                    throw new Error('WebSocket未连接');
                }
                
                // 等待session真正启动成功
                await sessionStartPromise;
                
                isTextSessionActive = true;
                showLive2d();
                
                // 重新启用文本输入
                textSendButton.disabled = false;
                textInputBox.disabled = false;
                screenshotButton.disabled = false;
                
                statusElement.textContent = '正在文本聊天中';
            } catch (error) {
                console.error('启动文本session失败:', error);
                statusElement.textContent = `启动失败: ${error.message}`;
                
                // 重新启用按钮，允许用户重试
                textSendButton.disabled = false;
                textInputBox.disabled = false;
                screenshotButton.disabled = false;
                
                return; // 启动失败，不继续发送消息
            }
        }
        
        // 发送消息
        if (socket.readyState === WebSocket.OPEN) {
            // 先发送所有截图
            if (hasScreenshots) {
                const screenshotItems = Array.from(screenshotsList.children);
                for (const item of screenshotItems) {
                    const img = item.querySelector('.screenshot-thumbnail');
                    if (img && img.src) {
                        socket.send(JSON.stringify({
                            action: 'stream_data',
                            data: img.src,
                            input_type: isMobile() ? 'camera' : 'screen'
                        }));
                    }
                }
                
                // 在聊天界面显示截图提示
                const screenshotCount = screenshotItems.length;
                appendMessage(`📸 [已发送${screenshotCount}张截图]`, 'user', true);
                
                // 清空截图列表
                screenshotsList.innerHTML = '';
                screenshotThumbnailContainer.classList.remove('show');
                updateScreenshotCount();
            }
            
            // 再发送文本（如果有）
            if (text) {
                socket.send(JSON.stringify({
                    action: 'stream_data',
                    data: text,
                    input_type: 'text'
                }));
                
                // 清空输入框
                textInputBox.value = '';
                
                // 在聊天界面显示用户消息
                appendMessage(text, 'user', true);
            }
            
            // 文本聊天后，重置主动搭话计时器（如果已开启）
            if (proactiveChatEnabled) {
                resetProactiveChatBackoff();
            }
            
            statusElement.textContent = '正在文本聊天中';
        } else {
            statusElement.textContent = 'WebSocket未连接！';
        }
    });
    
    // 支持Enter键发送（Shift+Enter换行）
    textInputBox.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            textSendButton.click();
        }
    });
    
    // 截图按钮事件
    screenshotButton.addEventListener('click', async () => {
        try {
            // 临时禁用截图按钮，防止重复点击
            screenshotButton.disabled = true;
            statusElement.textContent = '正在截图...';
            
            let captureStream;
            
            // 获取屏幕或摄像头流
            if (isMobile()) {
                // 移动端使用摄像头
                captureStream = await getMobileCameraStream();
            } else {
                // 桌面端使用屏幕共享
                captureStream = await navigator.mediaDevices.getDisplayMedia({
                    video: {
                        cursor: 'always',
                    },
                    audio: false,
                });
            }
            
            // 创建video元素来加载流
            const video = document.createElement('video');
            video.srcObject = captureStream;
            video.autoplay = true;
            video.muted = true;
            
            // 等待视频加载完成
            await video.play();
            
            // 创建canvas来捕获帧
            const canvas = document.createElement('canvas');
            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
            const ctx = canvas.getContext('2d');
            
            // 捕获当前帧
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
            const dataUrl = canvas.toDataURL('image/jpeg', 0.8); // base64 jpeg
            
            // 停止捕获流
            captureStream.getTracks().forEach(track => track.stop());
            
            // 添加截图到待发送列表（不立即发送）
            addScreenshotToList(dataUrl);
            
            statusElement.textContent = '截图已添加，点击发送一起发送';
            
            // 重新启用截图按钮
            screenshotButton.disabled = false;
            
        } catch (err) {
            console.error('截图失败:', err);
            
            // 根据错误类型显示不同提示
            let errorMsg = '截图失败';
            if (err.name === 'NotAllowedError') {
                errorMsg = '用户取消了截图';
            } else if (err.name === 'NotFoundError') {
                errorMsg = '未找到可用的媒体设备';
            } else if (err.name === 'NotReadableError') {
                errorMsg = '无法访问媒体设备';
            } else if (err.message) {
                errorMsg = `截图失败: ${err.message}`;
            }
            
            statusElement.textContent = errorMsg;
            
            // 重新启用截图按钮
            screenshotButton.disabled = false;
        }
    });
    
    // 添加截图到列表
    function addScreenshotToList(dataUrl) {
        screenshotCounter++;
        
        // 创建截图项容器
        const item = document.createElement('div');
        item.className = 'screenshot-item';
        item.dataset.index = screenshotCounter;
        
        // 创建缩略图
        const img = document.createElement('img');
        img.className = 'screenshot-thumbnail';
        img.src = dataUrl;
        img.alt = `截图 ${screenshotCounter}`;
        img.title = `点击查看截图 ${screenshotCounter}`;
        
        // 点击缩略图可以在新标签页查看大图
        img.addEventListener('click', () => {
            window.open(dataUrl, '_blank');
        });
        
        // 创建删除按钮
        const removeBtn = document.createElement('button');
        removeBtn.className = 'screenshot-remove';
        removeBtn.innerHTML = '×';
        removeBtn.title = '移除此截图';
        removeBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            removeScreenshotFromList(item);
        });
        
        // 创建索引标签
        const indexLabel = document.createElement('span');
        indexLabel.className = 'screenshot-index';
        indexLabel.textContent = `#${screenshotCounter}`;
        
        // 组装元素
        item.appendChild(img);
        item.appendChild(removeBtn);
        item.appendChild(indexLabel);
        
        // 添加到列表
        screenshotsList.appendChild(item);
        
        // 更新计数和显示容器
        updateScreenshotCount();
        screenshotThumbnailContainer.classList.add('show');
        
        // 自动滚动到最新的截图
        setTimeout(() => {
            screenshotsList.scrollLeft = screenshotsList.scrollWidth;
        }, 100);
    }
    
    // 从列表中移除截图
    function removeScreenshotFromList(item) {
        item.style.animation = 'slideOut 0.3s ease';
        setTimeout(() => {
            item.remove();
            updateScreenshotCount();
            
            // 如果没有截图了，隐藏容器
            if (screenshotsList.children.length === 0) {
                screenshotThumbnailContainer.classList.remove('show');
            }
        }, 300);
    }
    
    // 更新截图计数
    function updateScreenshotCount() {
        const count = screenshotsList.children.length;
        screenshotCount.textContent = count;
    }
    
    // 清空所有截图
    clearAllScreenshots.addEventListener('click', () => {
        if (screenshotsList.children.length === 0) return;
        
        if (confirm('确定要清空所有待发送的截图吗？')) {
            screenshotsList.innerHTML = '';
            screenshotThumbnailContainer.classList.remove('show');
            updateScreenshotCount();
        }
    });

    // 情感分析功能
    async function analyzeEmotion(text) {
        console.log('analyzeEmotion被调用，文本:', text);
        try {
            const response = await fetch('/api/emotion/analysis', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    text: text,
                    lanlan_name: lanlan_config.lanlan_name
                })
            });

            if (!response.ok) {
                console.warn('情感分析请求失败:', response.status);
                return null;
            }

            const result = await response.json();
            console.log('情感分析API返回结果:', result);
            
            if (result.error) {
                console.warn('情感分析错误:', result.error);
                return null;
            }

            return result;
        } catch (error) {
            console.error('情感分析请求异常:', error);
            return null;
        }
    }

    // 应用情感到Live2D模型
    function applyEmotion(emotion) {
        if (window.LanLan1 && window.LanLan1.setEmotion) {
            console.log('调用window.LanLan1.setEmotion:', emotion);
            window.LanLan1.setEmotion(emotion);
        } else {
            console.warn('情感功能未初始化');
        }
    }

    // 启动麦克风静音检测
    function startSilenceDetection() {
        // 重置检测状态
        hasSoundDetected = false;
        
        // 清除之前的定时器(如果有)
        if (silenceDetectionTimer) {
            clearTimeout(silenceDetectionTimer);
        }
        
        // 启动5秒定时器
        silenceDetectionTimer = setTimeout(() => {
            if (!hasSoundDetected && isRecording) {
                statusElement.textContent = '⚠️ 麦克风无声音，请检查麦克风设置';
                console.warn('麦克风静音检测：5秒内未检测到声音');
            }
        }, 5000);
    }
    
    // 停止麦克风静音检测
    function stopSilenceDetection() {
        if (silenceDetectionTimer) {
            clearTimeout(silenceDetectionTimer);
            silenceDetectionTimer = null;
        }
        hasSoundDetected = false;
    }
    
    // 监测音频输入音量
    function monitorInputVolume() {
        if (!inputAnalyser || !isRecording) {
            return;
        }
        
        const dataArray = new Uint8Array(inputAnalyser.fftSize);
        inputAnalyser.getByteTimeDomainData(dataArray);
        
        // 计算音量(RMS)
        let sum = 0;
        for (let i = 0; i < dataArray.length; i++) {
            const val = (dataArray[i] - 128) / 128.0;
            sum += val * val;
        }
        const rms = Math.sqrt(sum / dataArray.length);
        
        // 如果音量超过阈值(0.01),认为检测到声音
        if (rms > 0.01) {
            if (!hasSoundDetected) {
                hasSoundDetected = true;
                console.log('麦克风静音检测：检测到声音，RMS =', rms);
                
                // 如果之前显示了无声音警告，现在检测到声音了，恢复正常状态显示
                if (statusElement.textContent.includes('麦克风无声音')) {
                    statusElement.textContent = '正在语音...';
                    console.log('麦克风静音检测：检测到声音，已清除警告');
                }
            }
        }
        
        // 持续监测
        if (isRecording) {
            requestAnimationFrame(monitorInputVolume);
        }
    }

    // 使用AudioWorklet开始音频处理
    async function startAudioWorklet(stream) {
        isRecording = true;

        // 创建音频上下文
        audioContext = new AudioContext();
        console.log("音频上下文采样率:", audioContext.sampleRate);

        // 创建媒体流源
        const source = audioContext.createMediaStreamSource(stream);
        
        // 创建analyser节点用于监测输入音量
        inputAnalyser = audioContext.createAnalyser();
        inputAnalyser.fftSize = 2048;
        inputAnalyser.smoothingTimeConstant = 0.8;
        
        // 连接source到analyser(用于音量检测)
        source.connect(inputAnalyser);

        try {
            // 加载AudioWorklet处理器
            await audioContext.audioWorklet.addModule('/static/audio-processor.js');

            // 创建AudioWorkletNode
            workletNode = new AudioWorkletNode(audioContext, 'audio-processor', {
                processorOptions: {
                    originalSampleRate: audioContext.sampleRate,
                    targetSampleRate: 16000
                }
            });

            // 监听处理器发送的消息
            workletNode.port.onmessage = (event) => {
                const audioData = event.data;

                // 新增逻辑：focusModeEnabled为true且正在播放语音时，不回传麦克风音频
                if (focusModeEnabled === true && isPlaying === true) {
                    // 处于focus模式且语音播放中，跳过回传
                    return;
                }

                if (isRecording && socket.readyState === WebSocket.OPEN) {
                    socket.send(JSON.stringify({
                        action: 'stream_data',
                        data: Array.from(audioData),
                        input_type: 'audio'
                    }));
                }
            };

            // 连接节点
            source.connect(workletNode);
            // 不需要连接到destination，因为我们不需要听到声音
            // workletNode.connect(audioContext.destination);
            
            // 启动静音检测
            startSilenceDetection();
            monitorInputVolume();

        } catch (err) {
            console.error('加载AudioWorklet失败:', err);
            console.dir(err); // <--- 使用 console.dir()
            statusElement.textContent = 'AudioWorklet加载失败';
            stopSilenceDetection();
        }
    }


    // 停止录屏
    function stopScreening() {
        if (videoSenderInterval) clearInterval(videoSenderInterval);
    }

    // 停止录音
    function stopRecording() {

        stopScreening();
        if (!isRecording) return;

        isRecording = false;
        currentGeminiMessage = null;
        
        // 停止静音检测
        stopSilenceDetection();
        
        // 清理输入analyser
        inputAnalyser = null;

        // 停止所有轨道
        if (stream) {
            stream.getTracks().forEach(track => track.stop());
        }

        // 关闭AudioContext
        if (audioContext) {
            audioContext.close();
        }

        // 通知服务器暂停会话
        if (socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify({
                action: 'pause_session'
            }));
        }
        
        // 同步重置浮动麦克风按钮状态（恢复默认白色背景）
        const floatingMicBtn = document.getElementById('live2d-btn-mic');
        if (floatingMicBtn) {
            floatingMicBtn.dataset.active = 'false';
            floatingMicBtn.style.background = 'rgba(255, 255, 255, 0.9)';
        }
        
        // statusElement.textContent = '录制已停止';
    }

    // 清空音频队列并停止所有播放
    function clearAudioQueue() {
        // 停止所有计划的音频源
        scheduledSources.forEach(source => {
            try {
                source.stop();
            } catch (e) {
                // 忽略已经停止的源
            }
        });

        // 清空队列和计划源列表
        scheduledSources = [];
        audioBufferQueue = [];
        isPlaying = false;
        audioStartTime = 0;
        nextStartTime = 0; // 新增：重置预调度时间
    }


    function scheduleAudioChunks() {
        const scheduleAheadTime = 5;

        initializeGlobalAnalyser();

        // 关键：预调度所有在lookahead时间内的chunk
        while (nextChunkTime < audioPlayerContext.currentTime + scheduleAheadTime) {
            if (audioBufferQueue.length > 0) {
                const { buffer: nextBuffer } = audioBufferQueue.shift();
                console.log('ctx', audioPlayerContext.sampleRate,
                    'buf', nextBuffer.sampleRate);

                const source = audioPlayerContext.createBufferSource();
                source.buffer = nextBuffer;
                // source.connect(audioPlayerContext.destination);


                // 创建analyser节点用于lipSync
                // const analyser = audioPlayerContext.createAnalyser();
                // analyser.fftSize = 2048;
                // source.connect(analyser);
                // analyser.connect(audioPlayerContext.destination);
                // if (window.LanLan1 && window.LanLan1.live2dModel) {
                //     startLipSync(window.LanLan1.live2dModel, analyser);
                // }


                source.connect(globalAnalyser);

                if (!lipSyncActive && window.LanLan1 && window.LanLan1.live2dModel) {
                    startLipSync(window.LanLan1.live2dModel, globalAnalyser);
                    lipSyncActive = true;
                }

                // 精确时间调度
                source.start(nextChunkTime);
                // console.log(`调度chunk在时间: ${nextChunkTime.toFixed(3)}`);

                // 设置结束回调处理lipSync停止
                source.onended = () => {
                    // if (window.LanLan1 && window.LanLan1.live2dModel) {
                    //     stopLipSync(window.LanLan1.live2dModel);
                    // }
                    const index = scheduledSources.indexOf(source);
                    if (index !== -1) {
                        scheduledSources.splice(index, 1);
                    }

                    if (scheduledSources.length === 0 && audioBufferQueue.length === 0) {
                        if (window.LanLan1 && window.LanLan1.live2dModel) {
                            stopLipSync(window.LanLan1.live2dModel);
                        }
                        lipSyncActive = false;
                        isPlaying = false; // 新增：所有音频播放完毕，重置isPlaying
                    }
                };

                // // 更新下一个chunk的时间
                nextChunkTime += nextBuffer.duration;

                scheduledSources.push(source);
            } else {
                break;
            }
        }

        // 继续调度循环
        setTimeout(scheduleAudioChunks, 25); // 25ms间隔检查
    }


    async function handleAudioBlob(blob) {
        // 你现有的PCM处理代码...
        const pcmBytes = await blob.arrayBuffer();
        if (!pcmBytes || pcmBytes.byteLength === 0) {
            console.warn('收到空的PCM数据，跳过处理');
            return;
        }

        if (!audioPlayerContext) {
            audioPlayerContext = new (window.AudioContext || window.webkitAudioContext)();
        }

        if (audioPlayerContext.state === 'suspended') {
            await audioPlayerContext.resume();
        }

        const int16Array = new Int16Array(pcmBytes);
        const audioBuffer = audioPlayerContext.createBuffer(1, int16Array.length, 48000);
        const channelData = audioBuffer.getChannelData(0);
        for (let i = 0; i < int16Array.length; i++) {
            channelData[i] = int16Array[i] / 32768.0;
        }

        const bufferObj = { seq: seqCounter++, buffer: audioBuffer };
        audioBufferQueue.push(bufferObj);

        let i = audioBufferQueue.length - 1;
        while (i > 0 && audioBufferQueue[i].seq < audioBufferQueue[i - 1].seq) {
            [audioBufferQueue[i], audioBufferQueue[i - 1]] =
              [audioBufferQueue[i - 1], audioBufferQueue[i]];
            i--;
        }

        // 如果是第一次，初始化调度
        if (!isPlaying) {
            nextChunkTime = audioPlayerContext.currentTime + 0.1;
            isPlaying = true;
            scheduleAudioChunks(); // 开始调度循环
        }
    }

    function startScreenVideoStreaming(stream, input_type) {
        const video = document.createElement('video');
        // console.log('Ready for sharing 1')

        video.srcObject = stream;
        video.autoplay = true;
        video.muted = true;
        // console.log('Ready for sharing 2')

        videoTrack = stream.getVideoTracks()[0];
        const canvas = document.createElement('canvas');
        const ctx = canvas.getContext('2d');

        // 定时抓取当前帧并编码为jpeg
        video.play().then(() => {
            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
            videoSenderInterval = setInterval(() => {
                ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
                const dataUrl = canvas.toDataURL('image/jpeg', 0.8); // base64 jpeg

                if (socket.readyState === WebSocket.OPEN) {
                    socket.send(JSON.stringify({
                        action: 'stream_data',
                        data: dataUrl,
                        input_type: input_type,
                    }));
                }
            }, 1000); } // 每100ms一帧
        )
    }

    function initializeGlobalAnalyser() {
        if (!globalAnalyser && audioPlayerContext) {
            globalAnalyser = audioPlayerContext.createAnalyser();
            globalAnalyser.fftSize = 2048;
            globalAnalyser.connect(audioPlayerContext.destination);
        }
    }

    // ========== 增强口型同步系统 ==========
    // 平滑参数
    let smoothedMouthOpen = 0;
    let smoothedMouthForm = 0;
    const smoothingFactor = 0.3; // 平滑系数，越小越平滑
    const minThreshold = 0.02;   // 静音阈值
    
    function startLipSync(model, analyser) {
        // 使用频率数据进行更精确的口型分析
        const frequencyData = new Uint8Array(analyser.frequencyBinCount);
        const timeData = new Uint8Array(analyser.fftSize);
        const sampleRate = audioPlayerContext?.sampleRate || 44100;
        const binSize = sampleRate / analyser.fftSize;
        
        function animate() {
            // 获取频率域和时域数据
            analyser.getByteFrequencyData(frequencyData);
            analyser.getByteTimeDomainData(timeData);
            
            // 1. 计算RMS音量（基础开口度）
            let sum = 0;
            for (let i = 0; i < timeData.length; i++) {
                const val = (timeData[i] - 128) / 128;
                sum += val * val;
            }
            const rms = Math.sqrt(sum / timeData.length);
            
            // 静音检测
            if (rms < minThreshold) {
                // 平滑过渡到闭嘴
                smoothedMouthOpen = smoothedMouthOpen * 0.85;
                if (smoothedMouthOpen < 0.01) smoothedMouthOpen = 0;
                
                if (window.LanLan1 && typeof window.LanLan1.setMouth === 'function') {
                    window.LanLan1.setMouth(smoothedMouthOpen);
                }
                animationFrameId = requestAnimationFrame(animate);
                return;
            }
            
            // 2. 频段能量分析（区分元音/辅音特征）
            // 低频段 (100-500Hz): 基频，对应开口大小
            // 中低频段 (500-1500Hz): 第一共振峰，中文元音特征明显
            // 中高频段 (1500-3500Hz): 第二共振峰，英文元音区分
            // 高频段 (3500-8000Hz): 辅音摩擦音
            
            const lowBand = getFrequencyBandEnergy(frequencyData, 100, 500, binSize);
            const midLowBand = getFrequencyBandEnergy(frequencyData, 500, 1500, binSize);
            const midHighBand = getFrequencyBandEnergy(frequencyData, 1500, 3500, binSize);
            const highBand = getFrequencyBandEnergy(frequencyData, 3500, 8000, binSize);
            
            // 3. 计算开口度 (ParamMouthOpenY)
            // 元音开口大: 低频+中低频能量高
            // 辅音开口小: 高频能量占比高
            const vowelness = (lowBand + midLowBand) / (lowBand + midLowBand + midHighBand + highBand + 0.001);
            
            // 基础开口度 = RMS * 放大系数
            let baseMouthOpen = Math.min(1, rms * 6);
            
            // 根据频谱特征调整
            // 元音（vowelness高）-> 开口更大
            // 辅音（vowelness低，highBand高）-> 开口更小但更快速
            let targetMouthOpen = baseMouthOpen * (0.5 + vowelness * 0.7);
            
            // 高频摩擦音增强（辅音快速开合）
            if (highBand > midLowBand * 0.5) {
                targetMouthOpen = Math.max(targetMouthOpen, baseMouthOpen * 0.4);
            }
            
            // 4. 计算嘴型形状 (ParamMouthForm: -1=悲伤/圆口, 1=微笑/扁口)
            // 中文: "a,o,e" 偏圆口，"i,u" 偏扁口
            // 英文: 类似但共振峰位置不同
            // 通过中高频和中低频比例判断
            let targetMouthForm = 0;
            if (midLowBand > 0.1) {
                // F2/F1 比值高 -> 扁口（前元音 i, e）
                // F2/F1 比值低 -> 圆口（后元音 o, u）
                const formantRatio = midHighBand / (midLowBand + 0.001);
                targetMouthForm = Math.min(1, Math.max(-1, (formantRatio - 1) * 0.5));
            }
            
            // 5. 应用平滑过渡（防止抖动）
            smoothedMouthOpen += (targetMouthOpen - smoothedMouthOpen) * smoothingFactor;
            smoothedMouthForm += (targetMouthForm - smoothedMouthForm) * smoothingFactor * 0.5;
            
            // 限制范围
            smoothedMouthOpen = Math.min(1, Math.max(0, smoothedMouthOpen));
            smoothedMouthForm = Math.min(1, Math.max(-1, smoothedMouthForm));
            
            // 6. 设置Live2D参数
            if (window.LanLan1 && typeof window.LanLan1.setMouth === 'function') {
                window.LanLan1.setMouth(smoothedMouthOpen);
            }
            
            // 同时设置嘴型形状（如果模型支持）
            if (window.LanLan1?.live2dModel?.internalModel?.coreModel) {
                try {
                    window.LanLan1.live2dModel.internalModel.coreModel
                        .setParameterValueById('ParamMouthForm', smoothedMouthForm);
                } catch (_) {}
            }
            
            animationFrameId = requestAnimationFrame(animate);
        }
        
        animate();
    }
    
    // 辅助函数：获取指定频率范围的平均能量
    function getFrequencyBandEnergy(frequencyData, minFreq, maxFreq, binSize) {
        const minBin = Math.floor(minFreq / binSize);
        const maxBin = Math.min(Math.floor(maxFreq / binSize), frequencyData.length - 1);
        
        if (minBin >= maxBin) return 0;
        
        let sum = 0;
        let count = 0;
        for (let i = minBin; i <= maxBin; i++) {
            sum += frequencyData[i] / 255; // 归一化到 0-1
            count++;
        }
        
        return count > 0 ? sum / count : 0;
    }

    function stopLipSync(model) {
        cancelAnimationFrame(animationFrameId);
            
        // 重置平滑变量
        smoothedMouthOpen = 0;
        smoothedMouthForm = 0;
            
        if (window.LanLan1 && typeof window.LanLan1.setMouth === 'function') {
            window.LanLan1.setMouth(0);
        }
            
        // 同时重置嘴型形状
        if (window.LanLan1?.live2dModel?.internalModel?.coreModel) {
            try {
                window.LanLan1.live2dModel.internalModel.coreModel
                    .setParameterValueById('ParamMouthOpenY', 0);
                window.LanLan1.live2dModel.internalModel.coreModel
                    .setParameterValueById('ParamMouthForm', 0);
            } catch (_) {}
        } else if (model?.internalModel?.coreModel) {
            // 兆底
            try { 
                model.internalModel.coreModel.setParameterValueById('ParamMouthOpenY', 0);
                model.internalModel.coreModel.setParameterValueById('ParamMouthForm', 0);
            } catch (_) {}
        }
    }

    // 隐藏live2d函数
    function hideLive2d() {
        const container = document.getElementById('live2d-container');
        container.classList.add('minimized');
    }

    // 显示live2d函数
    function showLive2d() {
        const container = document.getElementById('live2d-container');

        // 判断是否已经最小化（通过检查是否有hidden类或检查样式）
        if (!container.classList.contains('minimized') &&
            container.style.visibility !== 'minimized') {
            // 如果已经显示，则不执行任何操作
            return;
        }

        // 重置"请她离开"状态
        if (window.live2d) {
            window.live2d._goodbyeClicked = false;
        }
        
        // 清除强制隐藏的样式
        const floatingButtons = document.getElementById('live2d-floating-buttons');
        if (floatingButtons) {
            floatingButtons.style.removeProperty('display');
            floatingButtons.style.removeProperty('visibility');
            floatingButtons.style.removeProperty('opacity');
        }
        
        const lockIcon = document.getElementById('live2d-lock-icon');
        if (lockIcon) {
            lockIcon.style.removeProperty('display');
            lockIcon.style.removeProperty('visibility');
            lockIcon.style.removeProperty('opacity');
        }
        
        // 恢复 sidebar、sidebarbox 和旧按钮，但保持它们隐藏
        // 这些是旧的按钮面板，应该始终隐藏，只用于功能触发
        const sidebar = document.getElementById('sidebar');
        const sidebarbox = document.getElementById('sidebarbox');
        
        if (sidebar) {
            sidebar.style.removeProperty('visibility');
            sidebar.style.removeProperty('opacity');
            sidebar.style.display = 'none'; // 保持隐藏
        }
        
        if (sidebarbox) {
            sidebarbox.style.removeProperty('visibility');
            sidebarbox.style.removeProperty('opacity');
            sidebarbox.style.display = 'none'; // 保持隐藏
        }
        
        const sideButtons = document.querySelectorAll('.side-btn');
        sideButtons.forEach(btn => {
            btn.style.removeProperty('visibility');
            btn.style.removeProperty('opacity');
            btn.style.display = 'none'; // 保持隐藏
        });

        // 先恢复容器尺寸和可见性，但保持透明度为0和位置在屏幕外
        // container.style.height = '1080px';
        // container.style.width = '720px';
        container.style.visibility = 'visible';

        // 强制浏览器重新计算样式，确保过渡效果正常
        void container.offsetWidth;

        // 移除hidden类，触发过渡动画
        container.classList.remove('minimized');
    }
    window.startScreenSharing = startScreenSharing;
    window.stopScreenSharing  = stopScreenSharing;
    window.screen_share       = startScreenSharing;
    
    // ========== 连接浮动按钮到原有功能 ==========
    
    // 麦克风按钮（toggle模式）
    window.addEventListener('live2d-mic-toggle', async (e) => {
        if (e.detail.active) {
            // 开始语音
            micButton.click(); // 触发原有的麦克风按钮点击
        } else {
            // 停止语音
            muteButton.click(); // 触发原有的停止按钮点击
        }
    });
    
    // 屏幕分享按钮（toggle模式）
    window.addEventListener('live2d-screen-toggle', async (e) => {
        if (e.detail.active) {
            // 开启屏幕分享
            screenButton.click();
        } else {
            // 关闭屏幕分享
            stopButton.click();
        }
    });
    
    // Agent工具按钮（只展开弹出框，不执行操作）
    window.addEventListener('live2d-agent-click', () => {
        // 不执行任何操作，只是展开弹出框
        console.log('Agent工具按钮被点击，显示弹出框');
    });
    
    // 设置按钮 - 填充弹出框内容
    let settingsPopupInitialized = false;
    window.addEventListener('live2d-settings-click', () => {
        console.log('设置按钮被点击');
        
        // 仅第一次点击时填充内容
        if (!settingsPopupInitialized) {
            const popup = document.getElementById('live2d-popup-settings');
            if (popup) {
                // 清空现有内容
                popup.innerHTML = '';
                
                // 创建设置项容器
                const container = document.createElement('div');
                container.style.cssText = 'min-width: 200px; max-width: 300px;';
                
                // 主动搭话开关
                const proactiveChatDiv = document.createElement('div');
                proactiveChatDiv.style.cssText = 'padding: 10px 12px; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid rgba(0,0,0,0.1);';
                proactiveChatDiv.innerHTML = `
                    <span style="font-size: 14px;">💬 主动搭话</span>
                    <input type="checkbox" id="proactive-chat-toggle-l2d" style="cursor: pointer; width: 18px; height: 18px;">
                `;
                container.appendChild(proactiveChatDiv);
                
                // Focus模式开关
                const focusModeDiv = document.createElement('div');
                focusModeDiv.style.cssText = 'padding: 10px 12px; display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid rgba(0,0,0,0.1);';
                focusModeDiv.innerHTML = `
                    <span style="font-size: 14px;">🎯 Focus模式</span>
                    <input type="checkbox" id="focus-mode-toggle-l2d" style="cursor: pointer; width: 18px; height: 18px;">
                `;
                container.appendChild(focusModeDiv);
                
                // 页面链接
                const links = [
                    { href: `/memory_browser`, text: '📝 记忆管理' },
                    { href: `/chara_manager`, text: '👤 角色设置' },
                    { href: `/l2d?lanlan_name=${lanlan_config.lanlan_name}`, text: '🎨 Live2D管理' },
                    { href: `/api_key`, text: '🔑 API设置' }
                ];
                
                links.forEach(link => {
                    const linkDiv = document.createElement('a');
                    linkDiv.href = link.href;
                    linkDiv.target = '_blank';
                    linkDiv.style.cssText = 'display: block; padding: 10px 12px; text-decoration: none; color: #333; font-size: 14px; border-bottom: 1px solid rgba(0,0,0,0.05); transition: background 0.2s;';
                    linkDiv.textContent = link.text;
                    linkDiv.onmouseenter = () => linkDiv.style.background = 'rgba(79, 140, 255, 0.1)';
                    linkDiv.onmouseleave = () => linkDiv.style.background = 'transparent';
                    container.appendChild(linkDiv);
                });
                
                popup.appendChild(container);
                
                // 设置初始状态
                const proactiveChatToggle = document.getElementById('proactive-chat-toggle-l2d');
                const focusModeToggle = document.getElementById('focus-mode-toggle-l2d');
                
                if (proactiveChatToggle) {
                    proactiveChatToggle.checked = proactiveChatEnabled;
                    proactiveChatToggle.addEventListener('change', (event) => {
                        event.stopPropagation();
                        proactiveChatEnabled = event.target.checked;
                        window.proactiveChatEnabled = proactiveChatEnabled; // 同步到全局
                        saveSettings();
                        
                        console.log(`主动搭话已${proactiveChatEnabled ? '开启' : '关闭'}`);
                        
                        if (proactiveChatEnabled) {
                            resetProactiveChatBackoff();
                        } else {
                            stopProactiveChatSchedule();
                        }
                    });
                }
                
                if (focusModeToggle) {
                    focusModeToggle.checked = focusModeEnabled;
                    focusModeToggle.addEventListener('change', (event) => {
                        event.stopPropagation();
                        focusModeEnabled = event.target.checked;
                        window.focusModeEnabled = focusModeEnabled; // 同步到全局
                        saveSettings();
                        
                        console.log(`Focus模式已${focusModeEnabled ? '开启' : '关闭'}`);
                    });
                }
                
                settingsPopupInitialized = true;
                console.log('设置弹出框已初始化');
            }
        }
    });
    
    // 睡觉按钮（请她离开）
    window.addEventListener('live2d-goodbye-click', () => {
        console.log('[App] 请她离开按钮被点击，开始隐藏所有按钮');
        
        // 第一步：立即设置标志位，防止任何后续逻辑显示按钮
        if (window.live2d) {
            window.live2d._goodbyeClicked = true;
        }
        
        // 停止主动搭话定时器
        stopProactiveChatSchedule();
        console.log('[App] 已停止主动搭话定时器');
        
        // 第二步：立即隐藏所有浮动按钮和锁按钮（设置为 !important 防止其他代码覆盖）
        const floatingButtons = document.getElementById('live2d-floating-buttons');
        if (floatingButtons) {
            floatingButtons.style.setProperty('display', 'none', 'important');
            floatingButtons.style.setProperty('visibility', 'hidden', 'important');
            floatingButtons.style.setProperty('opacity', '0', 'important');
        }
        
        const lockIcon = document.getElementById('live2d-lock-icon');
        if (lockIcon) {
            lockIcon.style.setProperty('display', 'none', 'important');
            lockIcon.style.setProperty('visibility', 'hidden', 'important');
            lockIcon.style.setProperty('opacity', '0', 'important');
        }
        
        // 第三步：立即隐藏所有 side-btn 按钮和侧边栏
        const sidebar = document.getElementById('sidebar');
        const sidebarbox = document.getElementById('sidebarbox');
        
        if (sidebar) {
            sidebar.style.setProperty('display', 'none', 'important');
            sidebar.style.setProperty('visibility', 'hidden', 'important');
            sidebar.style.setProperty('opacity', '0', 'important');
        }
        
        if (sidebarbox) {
            sidebarbox.style.setProperty('display', 'none', 'important');
            sidebarbox.style.setProperty('visibility', 'hidden', 'important');
            sidebarbox.style.setProperty('opacity', '0', 'important');
        }
        
        const sideButtons = document.querySelectorAll('.side-btn');
        sideButtons.forEach(btn => {
            btn.style.setProperty('display', 'none', 'important');
            btn.style.setProperty('visibility', 'hidden', 'important');
            btn.style.setProperty('opacity', '0', 'important');
        });
        
        // 第四步：自动折叠对话区
        const chatContainerEl = document.getElementById('chat-container');
        const toggleChatBtn = document.getElementById('toggle-chat-btn');
        if (chatContainerEl && !chatContainerEl.classList.contains('minimized')) {
            // 如果对话区当前是展开的，模拟点击折叠按钮
            if (toggleChatBtn) {
                toggleChatBtn.click();
            }
        }
        
        // 第五步：触发原有的离开逻辑（关闭会话并让live2d消失）
        if (resetSessionButton) {
            // 延迟一点点执行，确保隐藏操作已经生效
            setTimeout(() => {
                resetSessionButton.click();
            }, 10);
        } else {
            console.error('[App] ❌ resetSessionButton 未找到！');
        }
    });
    
    // ========== Agent控制逻辑 ==========
    
    // 浮动Agent status更新函数
    function setFloatingAgentStatus(msg) {
        const statusEl = document.getElementById('live2d-agent-status');
        if (statusEl) {
            statusEl.textContent = msg || '';
        }
    }
    
    // 检查Agent服务器健康状态
    async function checkToolServerHealth() {
        try {
            const resp = await fetch(`/api/agent/health`);
            if (!resp.ok) throw new Error('not ok');
            return true;
        } catch (e) {
            return false;
        }
    }
    
    // 检查Agent能力
    async function checkCapability(kind, showError = true) {
        try {
            if (kind === 'computer_use') {
                const r = await fetch(`/api/agent/computer_use/availability`);
                if (!r.ok) return false;
                const j = await r.json();
                if (!j.ready) {
                    if (showError) {
                        setFloatingAgentStatus((j.reasons && j.reasons[0]) || '键鼠控制不可用');
                    }
                    return false;
                }
                return true;
            } else if (kind === 'mcp') {
                const r = await fetch(`/api/agent/mcp/availability`);
                if (!r.ok) return false;
                const j = await r.json();
                if (!j.ready) {
                    if (showError) {
                        setFloatingAgentStatus((j.reasons && j.reasons[0]) || 'MCP不可用');
                    }
                    return false;
                }
                return true;
            }
            return false;
        } catch (e) {
            return false;
        }
    }
    
    // 连接Agent弹出框中的开关到Agent控制逻辑
    setTimeout(() => {
        const agentMasterCheckbox = document.getElementById('live2d-agent-master');
        const agentKeyboardCheckbox = document.getElementById('live2d-agent-keyboard');
        const agentMcpCheckbox = document.getElementById('live2d-agent-mcp');
        
        if (!agentMasterCheckbox) return;
        
        // Agent总开关逻辑
        agentMasterCheckbox.addEventListener('change', async () => {
            if (agentMasterCheckbox.checked) {
                try {
                    const ok = await checkToolServerHealth();
                    if (!ok) throw new Error('tool server down');
                } catch (e) {
                    setFloatingAgentStatus('Agent服务器未启动');
                    agentMasterCheckbox.checked = false;
                    return;
                }
                setFloatingAgentStatus('Agent模式已开启');
                if (agentKeyboardCheckbox) agentKeyboardCheckbox.disabled = false;
                if (agentMcpCheckbox) agentMcpCheckbox.disabled = false;
                
                try {
                    const r = await fetch('/api/agent/flags', {
                        method:'POST', 
                        headers:{'Content-Type':'application/json'}, 
                        body: JSON.stringify({
                            lanlan_name: lanlan_config.lanlan_name, 
                            flags: {agent_enabled:true, computer_use_enabled:false, mcp_enabled:false}
                        })
                    });
                    if (!r.ok) throw new Error('main_server rejected');
                } catch(e) {
                    agentMasterCheckbox.checked = false;
                    if (agentKeyboardCheckbox) agentKeyboardCheckbox.disabled = true;
                    if (agentMcpCheckbox) agentMcpCheckbox.disabled = true;
                    setFloatingAgentStatus('开启失败');
                }
            } else {
                setFloatingAgentStatus('Agent模式已关闭');
                
                // 重置子开关
                if (agentKeyboardCheckbox) {
                    agentKeyboardCheckbox.checked = false;
                    agentKeyboardCheckbox.disabled = true;
                }
                if (agentMcpCheckbox) {
                    agentMcpCheckbox.checked = false;
                    agentMcpCheckbox.disabled = true;
                }
                
                // 停止所有任务并重置状态
                try {
                    await fetch('/api/agent/admin/control', {
                        method: 'POST', 
                        headers: {'Content-Type': 'application/json'}, 
                        body: JSON.stringify({action: 'end_all'})
                    });
                    
                    await fetch('/api/agent/flags', {
                        method: 'POST', 
                        headers: {'Content-Type': 'application/json'}, 
                        body: JSON.stringify({
                            lanlan_name: lanlan_config.lanlan_name, 
                            flags: {agent_enabled: false, computer_use_enabled: false, mcp_enabled: false}
                        })
                    });
                } catch(e) {
                    setFloatingAgentStatus('Agent模式已关闭（部分清理失败）');
                }
            }
        });
        
        // 键鼠控制开关逻辑
        if (agentKeyboardCheckbox) {
            agentKeyboardCheckbox.addEventListener('change', async () => {
                if (agentKeyboardCheckbox.checked) {
                    try {
                        const ok = await checkCapability('computer_use');
                        if (!ok) throw new Error('not available');
                    } catch (e) {
                        setFloatingAgentStatus('键鼠控制不可用');
                        agentKeyboardCheckbox.checked = false;
                        return;
                    }
                    try {
                        const r = await fetch('/api/agent/flags', {
                            method:'POST', 
                            headers:{'Content-Type':'application/json'}, 
                            body: JSON.stringify({
                                lanlan_name: lanlan_config.lanlan_name, 
                                flags: {computer_use_enabled:true}
                            })
                        });
                        if (!r.ok) throw new Error('main_server rejected');
                        setFloatingAgentStatus('键鼠控制已开启');
                    } catch(e) {
                        agentKeyboardCheckbox.checked = false;
                        setFloatingAgentStatus('键鼠控制开启失败');
                    }
                } else {
                    setFloatingAgentStatus('键鼠控制已关闭');
                    try { 
                        await fetch('/api/agent/flags', {
                            method:'POST', 
                            headers:{'Content-Type':'application/json'}, 
                            body: JSON.stringify({
                                lanlan_name: lanlan_config.lanlan_name, 
                                flags: {computer_use_enabled:false}
                            })
                        }); 
                    } catch(e){}
                }
            });
        }
        
        // MCP工具开关逻辑
        if (agentMcpCheckbox) {
            agentMcpCheckbox.addEventListener('change', async () => {
                if (agentMcpCheckbox.checked) {
                    try {
                        const ok = await checkCapability('mcp');
                        if (!ok) throw new Error('not available');
                    } catch (e) {
                        setFloatingAgentStatus('MCP插件不可用');
                        agentMcpCheckbox.checked = false;
                        return;
                    }
                    try {
                        const r = await fetch('/api/agent/flags', {
                            method:'POST', 
                            headers:{'Content-Type':'application/json'}, 
                            body: JSON.stringify({
                                lanlan_name: lanlan_config.lanlan_name, 
                                flags: {mcp_enabled:true}
                            })
                        });
                        if (!r.ok) throw new Error('main_server rejected');
                        setFloatingAgentStatus('MCP插件已开启');
                    } catch(e) {
                        agentMcpCheckbox.checked = false;
                        setFloatingAgentStatus('MCP开启失败');
                    }
                } else {
                    setFloatingAgentStatus('MCP插件已关闭');
                    try { 
                        await fetch('/api/agent/flags', {
                            method:'POST', 
                            headers:{'Content-Type':'application/json'}, 
                            body: JSON.stringify({
                                lanlan_name: lanlan_config.lanlan_name, 
                                flags: {mcp_enabled:false}
                            })
                        }); 
                    } catch(e){}
                }
            });
        }
    }, 1000); // 延迟执行，确保浮动按钮已创建
    
    // 为浮动弹出框渲染麦克风列表（直接使用麦克风数据，不依赖原列表）
    window.renderFloatingMicList = async () => {
        const micPopup = document.getElementById('live2d-mic-popup');
        if (!micPopup) {
            console.log('麦克风弹出框未找到');
            return false;
        }
        
        try {
            // 直接获取麦克风设备
            const devices = await navigator.mediaDevices.enumerateDevices();
            const audioInputs = devices.filter(device => device.kind === 'audioinput');
            
            micPopup.innerHTML = '';
            
            if (audioInputs.length === 0) {
                const noMicItem = document.createElement('div');
                noMicItem.textContent = '没有检测到麦克风设备';
                noMicItem.style.padding = '8px 12px';
                noMicItem.style.color = '#666';
                noMicItem.style.fontSize = '13px';
                micPopup.appendChild(noMicItem);
                return false;
            }
            
            // 添加默认麦克风选项
            const defaultOption = document.createElement('button');
            defaultOption.className = 'mic-option';
            defaultOption.textContent = '系统默认麦克风';
            if (selectedMicrophoneId === null) {
                defaultOption.classList.add('selected');
            }
            Object.assign(defaultOption.style, {
                padding: '8px 12px',
                cursor: 'pointer',
                border: 'none',
                background: selectedMicrophoneId === null ? '#e6f0ff' : 'transparent',
                borderRadius: '6px',
                transition: 'background 0.2s ease',
                fontSize: '13px',
                width: '100%',
                textAlign: 'left',
                color: selectedMicrophoneId === null ? '#4f8cff' : '#333',
                fontWeight: selectedMicrophoneId === null ? '500' : '400'
            });
            defaultOption.addEventListener('mouseenter', () => {
                if (selectedMicrophoneId !== null) {
                    defaultOption.style.background = 'rgba(79, 140, 255, 0.1)';
                }
            });
            defaultOption.addEventListener('mouseleave', () => {
                if (selectedMicrophoneId !== null) {
                    defaultOption.style.background = 'transparent';
                }
            });
            defaultOption.addEventListener('click', async () => {
                await selectMicrophone(null);
                window.renderFloatingMicList();
            });
            micPopup.appendChild(defaultOption);
            
            // 添加分隔线
            const separator = document.createElement('div');
            separator.style.height = '1px';
            separator.style.backgroundColor = '#eee';
            separator.style.margin = '5px 0';
            micPopup.appendChild(separator);
            
            // 添加各个麦克风设备选项
            audioInputs.forEach(device => {
                const option = document.createElement('button');
                option.className = 'mic-option';
                option.textContent = device.label || `麦克风 ${audioInputs.indexOf(device) + 1}`;
                if (selectedMicrophoneId === device.deviceId) {
                    option.classList.add('selected');
                }
                
                Object.assign(option.style, {
                    padding: '8px 12px',
                    cursor: 'pointer',
                    border: 'none',
                    background: selectedMicrophoneId === device.deviceId ? '#e6f0ff' : 'transparent',
                    borderRadius: '6px',
                    transition: 'background 0.2s ease',
                    fontSize: '13px',
                    width: '100%',
                    textAlign: 'left',
                    color: selectedMicrophoneId === device.deviceId ? '#4f8cff' : '#333',
                    fontWeight: selectedMicrophoneId === device.deviceId ? '500' : '400'
                });
                
                option.addEventListener('mouseenter', () => {
                    if (selectedMicrophoneId !== device.deviceId) {
                        option.style.background = 'rgba(79, 140, 255, 0.1)';
                    }
                });
                option.addEventListener('mouseleave', () => {
                    if (selectedMicrophoneId !== device.deviceId) {
                        option.style.background = 'transparent';
                    }
                });
                
                option.addEventListener('click', async () => {
                    await selectMicrophone(device.deviceId);
                    window.renderFloatingMicList();
                });
                
                micPopup.appendChild(option);
            });
            
            return true;
        } catch (error) {
            console.error('获取麦克风列表失败:', error);
            micPopup.innerHTML = '';
            const errorItem = document.createElement('div');
            errorItem.textContent = '获取麦克风列表失败';
            errorItem.style.padding = '8px 12px';
            errorItem.style.color = '#dc3545';
            errorItem.style.fontSize = '13px';
            micPopup.appendChild(errorItem);
            return false;
        }
    };
    
    // 页面加载后初始化浮动麦克风列表（延迟确保弹出框已创建）
    setTimeout(() => {
        window.renderFloatingMicList();
    }, 1500);
    
    // 主动搭话定时触发功能
    function scheduleProactiveChat() {
        // 清除现有定时器
        if (proactiveChatTimer) {
            clearTimeout(proactiveChatTimer);
            proactiveChatTimer = null;
        }
        
        // 如果主动搭话未开启，不执行
        if (!proactiveChatEnabled) {
            return;
        }
        
        // 如果已点击"请她离开"，不执行主动搭话
        if (window.live2d && window.live2d._goodbyeClicked) {
            console.log('已点击"请她离开"，不安排主动搭话');
            return;
        }
        
        // 只在非语音模式下执行（语音模式下不触发主动搭话）
        // 文本模式或待机模式都可以触发主动搭话
        if (isRecording) {
            console.log('语音模式中，不安排主动搭话');
            return;
        }
        
        // 计算延迟时间（指数退避）
        const delay = PROACTIVE_CHAT_BASE_DELAY * Math.pow(2, proactiveChatBackoffLevel);
        console.log(`主动搭话：${delay / 1000}秒后触发（退避级别：${proactiveChatBackoffLevel}）`);
        
        proactiveChatTimer = setTimeout(async () => {
            console.log('触发主动搭话...');
            await triggerProactiveChat();
            
            // 增加退避级别（最多到4分钟，即level 3）
            if (proactiveChatBackoffLevel < 3) {
                proactiveChatBackoffLevel++;
            }
            
            // 安排下一次
            scheduleProactiveChat();
        }, delay);
    }
    
    async function triggerProactiveChat() {
        // 如果已点击"请她离开"，不执行主动搭话
        if (window.live2d && window.live2d._goodbyeClicked) {
            console.log('已点击"请她离开"，取消主动搭话');
            return;
        }
        
        try {
            const response = await fetch('/api/proactive_chat', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    lanlan_name: lanlan_config.lanlan_name
                })
            });
            
            const result = await response.json();
            
            if (result.success) {
                if (result.action === 'chat') {
                    console.log('主动搭话已发送:', result.message);
                    // 后端会直接通过session发送消息和TTS，前端无需处理显示
                } else if (result.action === 'pass') {
                    console.log('AI选择不搭话');
                }
            } else {
                console.warn('主动搭话失败:', result.error);
            }
        } catch (error) {
            console.error('主动搭话触发失败:', error);
        }
    }
    
    function resetProactiveChatBackoff() {
        // 如果已点击"请她离开"，不重新安排主动搭话
        if (window.live2d && window.live2d._goodbyeClicked) {
            console.log('已点击"请她离开"，不重新安排主动搭话');
            return;
        }
        
        // 重置退避级别
        proactiveChatBackoffLevel = 0;
        // 重新安排定时器
        scheduleProactiveChat();
    }
    
    function stopProactiveChatSchedule() {
        if (proactiveChatTimer) {
            clearTimeout(proactiveChatTimer);
            proactiveChatTimer = null;
        }
    }
    
    // 暴露函数到全局作用域，供 live2d.js 调用
    window.resetProactiveChatBackoff = resetProactiveChatBackoff;
    window.stopProactiveChatSchedule = stopProactiveChatSchedule;
    
    // 保存设置到localStorage
    function saveSettings() {
        const settings = {
            proactiveChatEnabled: proactiveChatEnabled,
            focusModeEnabled: focusModeEnabled
        };
        localStorage.setItem('xiao8_settings', JSON.stringify(settings));
    }
    
    // 从localStorage加载设置
    function loadSettings() {
        try {
            const saved = localStorage.getItem('xiao8_settings');
            if (saved) {
                const settings = JSON.parse(saved);
                proactiveChatEnabled = settings.proactiveChatEnabled || false;
                window.proactiveChatEnabled = proactiveChatEnabled; // 同步到全局
                // Focus模式：兼容URL传入的focus_mode或localStorage保存的设置
                if (typeof focus_mode !== 'undefined' && focus_mode === true) {
                    focusModeEnabled = true;
                } else {
                    focusModeEnabled = settings.focusModeEnabled || false;
                }
                window.focusModeEnabled = focusModeEnabled; // 同步到全局
            }
        } catch (error) {
            console.error('加载设置失败:', error);
        }
    }
    
    // 加载设置
    loadSettings();
    
    // 如果已开启主动搭话，立即启动定时器
    if (proactiveChatEnabled) {
        scheduleProactiveChat();
    }
} // 兼容老按钮

const ready = () => {
    if (ready._called) return;
    ready._called = true;
    init_app();
};

document.addEventListener("DOMContentLoaded", ready);
window.addEventListener("load", ready);

// ========== 外部音频播放接口 ==========
// 用于 Flutter 等外部应用传入 TTS 音频并播放，同步口型动画
(function() {
    let externalAudioContext = null;
    let externalAnalyser = null;
    let externalAnimationFrameId = null;
    let externalSmoothedMouthOpen = 0;
    let externalSmoothedMouthForm = 0;
    
    /**
     * 从 Base64 编码的音频数据播放并同步口型
     * @param {string} base64Audio - Base64 编码的音频数据 (MP3/WAV/OGG)
     * @param {string} format - 音频格式，默认 'mp3'
     */
    window.playExternalAudio = async function(base64Audio, format = 'mp3') {
        try {
            console.log('[ExternalAudio] 收到外部音频，长度:', base64Audio.length);
            
            // 初始化 AudioContext
            if (!externalAudioContext) {
                externalAudioContext = new (window.AudioContext || window.webkitAudioContext)();
            }
            
            if (externalAudioContext.state === 'suspended') {
                await externalAudioContext.resume();
            }
            
            // 解码 Base64 到 ArrayBuffer
            const binaryString = atob(base64Audio);
            const bytes = new Uint8Array(binaryString.length);
            for (let i = 0; i < binaryString.length; i++) {
                bytes[i] = binaryString.charCodeAt(i);
            }
            
            // 解码音频
            const audioBuffer = await externalAudioContext.decodeAudioData(bytes.buffer);
            
            // 创建音频源
            const source = externalAudioContext.createBufferSource();
            source.buffer = audioBuffer;
            
            // 创建分析器用于口型同步
            externalAnalyser = externalAudioContext.createAnalyser();
            externalAnalyser.fftSize = 2048;
            
            // 连接节点
            source.connect(externalAnalyser);
            externalAnalyser.connect(externalAudioContext.destination);
            
            // 启动口型同步
            startExternalLipSync();
            
            // 播放音频
            source.start(0);
            console.log('[ExternalAudio] 开始播放，时长:', audioBuffer.duration.toFixed(2), '秒');
            
            // 播放结束时停止口型同步
            source.onended = () => {
                console.log('[ExternalAudio] 播放结束');
                stopExternalLipSync();
            };
            
            return true;
        } catch (error) {
            console.error('[ExternalAudio] 播放失败:', error);
            return false;
        }
    };
    
    /**
     * 从 URL 播放音频并同步口型
     * @param {string} audioUrl - 音频文件 URL
     */
    window.playAudioFromUrl = async function(audioUrl) {
        try {
            console.log('[ExternalAudio] 从 URL 加载音频:', audioUrl);
            
            const response = await fetch(audioUrl);
            const arrayBuffer = await response.arrayBuffer();
            
            // 初始化 AudioContext
            if (!externalAudioContext) {
                externalAudioContext = new (window.AudioContext || window.webkitAudioContext)();
            }
            
            if (externalAudioContext.state === 'suspended') {
                await externalAudioContext.resume();
            }
            
            // 解码音频
            const audioBuffer = await externalAudioContext.decodeAudioData(arrayBuffer);
            
            // 创建音频源
            const source = externalAudioContext.createBufferSource();
            source.buffer = audioBuffer;
            
            // 创建分析器
            externalAnalyser = externalAudioContext.createAnalyser();
            externalAnalyser.fftSize = 2048;
            
            source.connect(externalAnalyser);
            externalAnalyser.connect(externalAudioContext.destination);
            
            startExternalLipSync();
            source.start(0);
            
            source.onended = () => {
                stopExternalLipSync();
            };
            
            return true;
        } catch (error) {
            console.error('[ExternalAudio] URL播放失败:', error);
            return false;
        }
    };
    
    function startExternalLipSync() {
        if (!externalAnalyser) return;
        
        const frequencyData = new Uint8Array(externalAnalyser.frequencyBinCount);
        const timeData = new Uint8Array(externalAnalyser.fftSize);
        const sampleRate = externalAudioContext?.sampleRate || 44100;
        const binSize = sampleRate / externalAnalyser.fftSize;
        const smoothingFactor = 0.3;
        const minThreshold = 0.02;
        
        function animate() {
            externalAnalyser.getByteFrequencyData(frequencyData);
            externalAnalyser.getByteTimeDomainData(timeData);
            
            // RMS音量
            let sum = 0;
            for (let i = 0; i < timeData.length; i++) {
                const val = (timeData[i] - 128) / 128;
                sum += val * val;
            }
            const rms = Math.sqrt(sum / timeData.length);
            
            // 静音检测
            if (rms < minThreshold) {
                externalSmoothedMouthOpen = externalSmoothedMouthOpen * 0.85;
                if (externalSmoothedMouthOpen < 0.01) externalSmoothedMouthOpen = 0;
                
                if (window.LanLan1 && typeof window.LanLan1.setMouth === 'function') {
                    window.LanLan1.setMouth(externalSmoothedMouthOpen);
                }
                externalAnimationFrameId = requestAnimationFrame(animate);
                return;
            }
            
            // 频段分析
            const lowBand = getBandEnergy(frequencyData, 100, 500, binSize);
            const midLowBand = getBandEnergy(frequencyData, 500, 1500, binSize);
            const midHighBand = getBandEnergy(frequencyData, 1500, 3500, binSize);
            const highBand = getBandEnergy(frequencyData, 3500, 8000, binSize);
            
            const vowelness = (lowBand + midLowBand) / (lowBand + midLowBand + midHighBand + highBand + 0.001);
            
            let baseMouthOpen = Math.min(1, rms * 6);
            let targetMouthOpen = baseMouthOpen * (0.5 + vowelness * 0.7);
            
            if (highBand > midLowBand * 0.5) {
                targetMouthOpen = Math.max(targetMouthOpen, baseMouthOpen * 0.4);
            }
            
            let targetMouthForm = 0;
            if (midLowBand > 0.1) {
                const formantRatio = midHighBand / (midLowBand + 0.001);
                targetMouthForm = Math.min(1, Math.max(-1, (formantRatio - 1) * 0.5));
            }
            
            externalSmoothedMouthOpen += (targetMouthOpen - externalSmoothedMouthOpen) * smoothingFactor;
            // Disable ParamMouthForm override to allow Motion Agent to control mouth shape (e.g. Sad/Happy)
            // externalSmoothedMouthForm += (targetMouthForm - externalSmoothedMouthForm) * smoothingFactor * 0.5;
            
            externalSmoothedMouthOpen = Math.min(1, Math.max(0, externalSmoothedMouthOpen));
            // externalSmoothedMouthForm = Math.min(1, Math.max(-1, externalSmoothedMouthForm));
            
            if (window.LanLan1 && typeof window.LanLan1.setMouth === 'function') {
                window.LanLan1.setMouth(externalSmoothedMouthOpen);
            }
            
            /* 
            // Disable aggressive ParamMouthForm overwrite. 
            // This prevents the lip-sync from canceling out the "Sad" (-1) or "Happy" (1) mouth forms set by the Motion Agent.
            if (window.LanLan1?.live2dModel?.internalModel?.coreModel) {
                try {
                    window.LanLan1.live2dModel.internalModel.coreModel
                        .setParameterValueById('ParamMouthForm', externalSmoothedMouthForm);
                } catch (_) {}
            }
            */
            
            externalAnimationFrameId = requestAnimationFrame(animate);
        }
        
        animate();
    }
    
    function stopExternalLipSync() {
        if (externalAnimationFrameId) {
            cancelAnimationFrame(externalAnimationFrameId);
            externalAnimationFrameId = null;
        }
        
        externalSmoothedMouthOpen = 0;
        externalSmoothedMouthForm = 0;
        
        if (window.LanLan1 && typeof window.LanLan1.setMouth === 'function') {
            window.LanLan1.setMouth(0);
        }
        
        if (window.LanLan1?.live2dModel?.internalModel?.coreModel) {
            try {
                window.LanLan1.live2dModel.internalModel.coreModel
                    .setParameterValueById('ParamMouthForm', 0);
            } catch (_) {}
        }
    }
    
    function getBandEnergy(frequencyData, minFreq, maxFreq, binSize) {
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
    
    // 暴露停止函数
    window.stopExternalAudio = stopExternalLipSync;
})();
