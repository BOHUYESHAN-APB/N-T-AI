function init_app(){
    // [Log Recorder] Send frontend errors to backend
    const sendLogToBackend = (msg, exc) => {
        try {
            fetch('/api/logs/frontend', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
            errors: [{
                timestamp: Date.now() / 1000,
                level: 'ERROR',
                message: msg,
                exception: exc
            }]
        })
            }).catch(() => {});
        } catch (_) {}
    };

    window.onerror = function(message, source, lineno, colno, error) {
        const msg = `[Global Error] ${message} (${source}:${lineno}:${colno})`;
        const exc = error ? error.stack : null;
        console.error(msg, exc);
        sendLogToBackend(msg, exc);
        return false;
    };

    window.onunhandledrejection = function(event) {
        const msg = `[Unhandled Promise] ${event.reason}`;
        console.error(msg, event.reason);
        sendLogToBackend(msg, event.reason ? event.reason.stack : null);
    };

    // Helper to safely get element
    const getEl = (id) => document.getElementById(id);

    const micButton = getEl('micButton');
    const muteButton = getEl('muteButton');
    const screenButton = getEl('screenButton');
    const stopButton = getEl('stopButton');
    const resetSessionButton = getEl('resetSessionButton');
    const statusElement = getEl('status') || { textContent: '' };
    const chatContainer = getEl('chat-container');
    const chatContentWrapper = getEl('chat-content-wrapper');
    const textInputBox = getEl('textInputBox');
    const textSendButton = getEl('textSendButton');
    const screenshotButton = getEl('screenshotButton');
    const screenshotThumbnailContainer = getEl('screenshot-thumbnail-container');
    const screenshotsList = getEl('screenshots-list');
    const screenshotCount = getEl('screenshot-count');
    const clearAllScreenshots = getEl('clear-all-screenshots');
    const isLiteMode = !chatContainer;
    window.live2dLiteMode = isLiteMode;

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
    let nextChunkTime = 0; // Added for client-side TTS scheduling
    let scheduledSources = [];
    let animationFrameId;
    let seqCounter = 0;
    let globalAnalyser = null;
    let lipSyncActive = false;
    
    // Client-side TTS Buffer
    // let ttsTextBuffer = "";
    // const sentenceDelimiters = /[.。！？\?!\n]+/;
    
    // async function playTTS(text) {
    //    ...
    // }
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
        const wsUrl = `${protocol}://${window.location.host}/api/live2d/ws`;
        // Old: const characterName = ... /ws/${characterName} -> This was causing 403 errors
        
        socket = new WebSocket(wsUrl);

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
                    const reasoning = response.reasoning_content || null;
                    const toolCalls = response.tool_calls || null;
                    appendMessage(response.text || '', 'gemini', isNewMessage, reasoning, toolCalls);
                    
                    // Reverted client-side TTS trigger
                    // Backend will broadcast 'audio' events

                } else if (response.type === 'chat_message') {
                    // Generic chat message (User, Chat, SC, Agent)
                    appendMessage(response.text, response.sender || 'chat_normal', true);

                } else if (response.type === 'user_transcript') {
                    // 处理用户语音转录，显示在聊天界面
                    appendMessage(response.text, 'user', true);
                } else if (response.type === 'user_activity') {
                    clearAudioQueue();
                } if (response.type === 'cozy_audio' || response.type === 'audio') {
                    if (!window.LIVE2D_DISABLE_WEBSOCKET_AUDIO) {
                        console.log("收到后端音频消息:", response.type);
                        const audioData = response.data || {};
                        if (typeof audioData.start_at === 'number') {
                            window.lastAudioStartAt = audioData.start_at;
                        }
                        if (window.playAudioBase64 && audioData.audio) {
                            window.playAudioBase64(audioData.audio);
                        } else if (window.playAudioUrl && audioData.url) {
                            window.playAudioUrl(audioData.url);
                        } else if (window.playAudioBase64 && response.audioData) {
                            window.playAudioBase64(response.audioData);
                        }
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
                    
                    // Flush remaining TTS
                    // if (ttsTextBuffer.trim().length > 0) {
                    //      console.log(`[Frontend TTS] Flushing remaining: "${ttsTextBuffer}"`);
                    //      playTTS(ttsTextBuffer, seqCounter++);
                    //      ttsTextBuffer = "";
                    // }

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
    function appendMessage(text, sender, isNewMessage = true, reasoning = null, toolCalls = null) {
        if (!chatContentWrapper) return;

        function getCurrentTimeString() {
            return new Date().toLocaleTimeString('en-US', {
                hour12: false,
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
        }

        // Map sender to CSS class and Icon
        let cssClass = sender;
        let icon = '';
        let showTimestamp = true;

        switch (sender) {
            case 'gemini':
            case 'ai':
                cssClass = 'gemini'; // Left
                icon = '🎀';
                break;
            case 'user':
                cssClass = 'user'; // Right
                icon = '💬';
                break;
            case 'chat_normal':
                cssClass = 'chat-normal'; // Center
                icon = ''; 
                showTimestamp = false; 
                break;
            case 'chat_sc':
                cssClass = 'chat-sc'; // Center Gold
                icon = '💰';
                break;
            case 'agent':
                cssClass = 'agent'; // Distinct Left
                icon = '🤖';
                break;
            default:
                // Keep original logic for unknown senders or 'system'
                if (sender === 'system') {
                    cssClass = 'system';
                    icon = '⚙️';
                }
        }

        if ((sender === 'gemini' || sender === 'ai') && !isNewMessage && currentGeminiMessage) {
            // Update existing Gemini message
            
            // 1. Update Reasoning if present
            if (reasoning) {
                let thinkingEl = currentGeminiMessage.querySelector('.thinking-content');
                if (!thinkingEl) {
                    // Create if missing (though should be created at start)
                    const thinkingContainer = document.createElement('div');
                    thinkingContainer.className = 'thinking-process expanded'; // Auto-expand on new stream
                    thinkingContainer.innerHTML = `
                        <div class="thinking-header" onclick="this.parentElement.classList.toggle('expanded')">
                            <span>💭 Thinking Process</span>
                        </div>
                        <div class="thinking-content"></div>
                    `;
                    currentGeminiMessage.insertBefore(thinkingContainer, currentGeminiMessage.firstChild);
                    thinkingEl = thinkingContainer.querySelector('.thinking-content');
                }
                thinkingEl.textContent += reasoning;
                
                // Show indicator in status bar
                updateStatus('Thinking...', 'thinking');
            }

            // 2. Update Tool Calls if present
            if (toolCalls && toolCalls.length > 0) {
                 // Append tool calls before text content but after thinking
                 toolCalls.forEach(tool => {
                     // Check if already rendered
                     if (!currentGeminiMessage.querySelector(`[data-tool-id="${tool.id}"]`)) {
                         const toolEl = document.createElement('div');
                         toolEl.className = 'tool-call';
                         toolEl.setAttribute('data-tool-id', tool.id);
                         toolEl.innerHTML = `<span class="tool-name">🛠️ Calling: ${tool.function.name}</span>`;
                         // Insert before the text content (last child usually)
                         currentGeminiMessage.insertBefore(toolEl, currentGeminiMessage.lastChild);
                     }
                 });
                 
                 updateStatus('Using Tools...', 'processing');
            }

            // 3. Update Content
            if (text) {
                let contentEl = currentGeminiMessage.querySelector('.message-content');
                if (!contentEl) {
                    contentEl = document.createElement('div');
                    contentEl.className = 'message-content';
                    currentGeminiMessage.appendChild(contentEl);
                }
                contentEl.insertAdjacentHTML('beforeend', text.replaceAll('\n', '<br>'));
                
                // Reset status if generating text
                updateStatus('Speaking...', 'processing');
            }

        } else {
            // Create new message
            const messageDiv = document.createElement('div');
            messageDiv.classList.add('message', cssClass);
            
            // Reasoning Section
            if (reasoning) {
                const thinkingContainer = document.createElement('div');
                thinkingContainer.className = 'thinking-process expanded';
                thinkingContainer.innerHTML = `
                    <div class="thinking-header" onclick="this.parentElement.classList.toggle('expanded')">
                        <span>💭 Thinking Process</span>
                    </div>
                    <div class="thinking-content">${reasoning}</div>
                `;
                messageDiv.appendChild(thinkingContainer);
            }

            // Tool Calls Section
            if (toolCalls && toolCalls.length > 0) {
                 toolCalls.forEach(tool => {
                     const toolEl = document.createElement('div');
                     toolEl.className = 'tool-call';
                     toolEl.setAttribute('data-tool-id', tool.id);
                     toolEl.innerHTML = `<span class="tool-name">🛠️ Calling: ${tool.function.name}</span>`;
                     messageDiv.appendChild(toolEl);
                 });
            }

            // Content Section
            const contentEl = document.createElement('div');
            contentEl.className = 'message-content';
            
            let htmlContent = '';
            if (showTimestamp) {
                htmlContent += `<strong>[${getCurrentTimeString()}] ${icon}</strong> <br>`;
            } else if (icon) {
                 htmlContent += `<strong>${icon}</strong> `;
            }
            
            htmlContent += text.replaceAll('\n', '<br>');
            contentEl.innerHTML = htmlContent;
            messageDiv.appendChild(contentEl);

            chatContentWrapper.appendChild(messageDiv);

            if (sender === 'gemini' || sender === 'ai') {
                currentGeminiMessage = messageDiv;
            }
        }
        chatContentWrapper.scrollTop = chatContentWrapper.scrollHeight;
    }

    try {
        window.appendMessage = appendMessage;
    } catch (_) {}

    // Helper to update status bar
    function updateStatus(text, type = 'normal') {
        const processIndicator = document.getElementById('process-indicator');
        const statusText = document.getElementById('status');
        
        if (statusText) statusText.textContent = text;
        
        if (processIndicator) {
            processIndicator.className = ''; // Reset
            if (type === 'thinking') processIndicator.classList.add('thinking');
            if (type === 'processing') processIndicator.classList.add('processing');
        }
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

    if (micButton) micButton.addEventListener('click', async () => {
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
            socket.send(JSON.stringify({
                action: 'start_session',
                input_type: 'audio'
            }));
            
            // 等待session真正启动成功
            await sessionStartPromise;
            
            // 开始录音
            await startMicCapture();
            
            // 只有在完全准备好后才显示"可以说话了"
            hideVoicePreparingToast();
            showReadyToSpeakToast();
            
        } catch (error) {
            console.error("启动语音会话失败:", error);
            statusElement.textContent = `启动失败: ${error.message}`;
            hideVoicePreparingToast();
            
            // 恢复按钮状态
            micButton.disabled = false;
            
            // 恢复文本输入区
            const textInputArea = document.getElementById('text-input-area');
            textInputArea.classList.remove('hidden');
        }
    });

    if (muteButton) muteButton.addEventListener('click', stopMicCapture);
    if (screenButton) screenButton.addEventListener('click', startScreenSharing);
    if (stopButton) stopButton.addEventListener('click', stopScreenSharing);

    if (resetSessionButton) resetSessionButton.addEventListener('click', () => {
        // 重置会话
        if (socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify({
                action: 'reset_session'
            }));
            statusElement.textContent = '会话已重置';
            
            // Clear chat
            if (chatContentWrapper) {
                chatContentWrapper.innerHTML = '<div class="message system">Session reset</div>';
                currentGeminiMessage = null;
            }
        }
    });
    
    // Toggle chat visibility
    const toggleChatBtn = getEl('toggle-chat-btn');
    if (toggleChatBtn && chatContainer) {
        toggleChatBtn.addEventListener('click', () => {
            chatContainer.classList.toggle('minimized');
            toggleChatBtn.textContent = chatContainer.classList.contains('minimized') ? '+' : '-';
        });
    }
    
    // Text input handling
    if (textSendButton && textInputBox) {
        const sendText = () => {
            const text = textInputBox.value.trim();
            if (!text) return;
            
            // 检查是否需要切换到文本模式
            if (!isTextSessionActive) {
                // 如果在录音，先停止录音
                if (isRecording) {
                    stopMicCapture();
                }
                
                // 发送start session事件 (text mode)
                if (socket.readyState === WebSocket.OPEN) {
                    socket.send(JSON.stringify({
                        action: 'start_session',
                        input_type: 'text'
                    }));
                    isTextSessionActive = true;
                    console.log('切换到文本对话模式');
                }
            }
            
            // Send text message
            if (socket.readyState === WebSocket.OPEN) {
                socket.send(JSON.stringify({
                    action: 'text_input',
                    text: text
                }));
                
                // Add to UI immediately
                appendMessage(text, 'user', true);
                textInputBox.value = '';
                
                // Reset proactive chat timer
                if (proactiveChatEnabled) {
                    resetProactiveChatBackoff();
                }
            }
        };
        
        textSendButton.addEventListener('click', sendText);
        textInputBox.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') sendText();
        });
    }

    // Screenshot functionality
    if (screenshotButton) {
        screenshotButton.addEventListener('click', async () => {
            try {
                // 如果已经在分享屏幕（录音模式下），直接使用当前流
                if (isRecording && screenCaptureStream) {
                    takeScreenshot(screenCaptureStream);
                } else {
                    // 文本模式下，临时获取屏幕流截图
                    // 显示提示
                    statusElement.textContent = '请选择要截图的窗口...';
                    
                    let tempStream;
                    if (isMobile()) {
                         tempStream = await getMobileCameraStream();
                    } else {
                        tempStream = await navigator.mediaDevices.getDisplayMedia({
                            video: { cursor: 'never' },
                            audio: false
                        });
                    }
                    
                    // 等待一小会儿确保流就绪
                    setTimeout(async () => {
                        await takeScreenshot(tempStream);
                        
                        // 停止临时流
                        tempStream.getTracks().forEach(track => track.stop());
                        statusElement.textContent = '截图已发送';
                    }, 500);
                }
            } catch (err) {
                console.error('截图失败:', err);
                statusElement.textContent = '截图取消或失败';
            }
        });
    }
    
    if (clearAllScreenshots) {
        clearAllScreenshots.addEventListener('click', () => {
            // 清除前端显示
            screenshotsList.innerHTML = '';
            screenshotCounter = 0;
            updateScreenshotCount();
            
            // 通知后端清除
            if (socket.readyState === WebSocket.OPEN) {
                socket.send(JSON.stringify({
                    action: 'clear_screenshots'
                }));
            }
        });
    }

    async function takeScreenshot(stream) {
        const track = stream.getVideoTracks()[0];
        const imageCapture = new ImageCapture(track);
        const bitmap = await imageCapture.grabFrame();
        
        // Convert to blob/base64
        const canvas = document.createElement('canvas');
        canvas.width = bitmap.width;
        canvas.height = bitmap.height;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(bitmap, 0, 0);
        
        const base64Data = canvas.toDataURL('image/jpeg', 0.8);
        
        // Add to UI list
        addScreenshotToUI(base64Data);
        
        // Send to backend
        if (socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify({
                action: 'image_input',
                image: base64Data
            }));
            console.log('截图已发送');
        }
    }
    
    function addScreenshotToUI(base64Data) {
        screenshotCounter++;
        
        const item = document.createElement('div');
        item.className = 'screenshot-item';
        item.innerHTML = `
            <img src="${base64Data}" alt="Screenshot ${screenshotCounter}">
            <div class="screenshot-remove" title="Remove">×</div>
        `;
        
        // Remove button handler
        item.querySelector('.screenshot-remove').addEventListener('click', () => {
            item.remove();
            screenshotCounter--;
            updateScreenshotCount();
            // Note: We don't remove from backend here effectively unless we track IDs
        });
        
        screenshotsList.appendChild(item);
        screenshotsList.scrollTop = screenshotsList.scrollHeight;
        
        updateScreenshotCount();
        
        // Show container if hidden
        if (screenshotThumbnailContainer.style.display === 'none') {
            screenshotThumbnailContainer.style.display = 'block';
        }
    }
    
    function updateScreenshotCount() {
        if (screenshotCount) {
            screenshotCount.textContent = screenshotCounter > 0 ? `${screenshotCounter} images` : '';
        }
        if (screenshotCounter === 0) {
            screenshotThumbnailContainer.style.display = 'none';
        } else {
            screenshotThumbnailContainer.style.display = 'flex';
        }
    }
}
