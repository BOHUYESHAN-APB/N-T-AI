import { strictFormat } from '../utils/text.js';

export class Ollama {
    static prefix = 'ollama';
    constructor(model_name, url, params) {
        this.model_name = model_name;
        this.params = params;
        
        // 优先使用传入的 url，然后是环境变量，最后是默认值
        // 支持通过 params 传递 ollama_url
        this.url = url || (params && params.ollama_url) || process.env.OLLAMA_URL || 'http://127.0.0.1:11434';
        
        this.chat_endpoint = '/api/chat';
        this.embedding_endpoint = '/api/embeddings';
    }

    async sendRequest(turns, systemMessage) {
        let model = this.model_name || 'sweaterdog/andy-4:micro-q8_0';
        let messages = strictFormat(turns);
        messages.unshift({ role: 'system', content: systemMessage });
        const maxAttempts = 5;
        let attempt = 0;
        let finalRes = null;

        while (attempt < maxAttempts) {
            attempt++;
            console.log(`Awaiting local response... (model: ${model}, attempt: ${attempt})`);
            let res = null;
            try {
                let apiResponse = await this.send(this.chat_endpoint, {
                    model: model,
                    messages: messages,
                    stream: false,
                    ...(this.params || {})
                });
                if (apiResponse) {
                    res = apiResponse['message']['content'];
                } else {
                    throw new Error('No response data from Ollama');
                }
            } catch (err) {
                if (err.message.toLowerCase().includes('context length') && turns.length > 1) {
                    console.log('Context length exceeded, trying again with shorter context.');
                    return await this.sendRequest(turns.slice(1), systemMessage);
                } else {
                    console.error('Ollama connection error:', err.message);
                    // 如果 Ollama 失败，且不是因为上下文长度，尝试回退到 MainBrain
                    console.warn('Attempting fallback to MainBrain...');
                    try {
                        const { MainBrain } = await import('./main_brain.js');
                        const mainBrain = new MainBrain(this.model_name, null, this.params);
                        return await mainBrain.sendRequest(turns, systemMessage);
                    } catch (fallbackErr) {
                        console.error('Fallback to MainBrain failed:', fallbackErr.message);
                        res = 'My brain disconnected, and fallback failed. Try again.';
                    }
                }
            }

            const hasOpenTag = res.includes("<think>");
            const hasCloseTag = res.includes("</think>");

            if ((hasOpenTag && !hasCloseTag)) {
                console.warn("Partial <think> block detected. Re-generating...");
                if (attempt < maxAttempts) continue;
            }
            if (hasCloseTag && !hasOpenTag) {
                res = '<think>' + res;
            }
            if (hasOpenTag && hasCloseTag) {
                res = res.replace(/<think>[\s\S]*?<\/think>/g, '').trim();
            }
            finalRes = res;
            break;
        }

        if (finalRes == null) {
            console.warn("Could not get a valid response after max attempts.");
            finalRes = 'I thought too hard, sorry, try again.';
        }
        return finalRes;
    }

    async embed(text) {
        let model = this.model_name || 'embeddinggemma';
        let body = { model: model, input: text };
        try {
            let res = await this.send(this.embedding_endpoint, body);
            if (res && res['embedding']) {
                return res['embedding'];
            }
            throw new Error('No embedding data from Ollama');
        } catch (err) {
            console.error('Ollama embedding error:', err.message);
            console.warn('Attempting fallback to MainBrain for embedding...');
            try {
                const { MainBrain } = await import('./main_brain.js');
                const mainBrain = new MainBrain(this.model_name, null, this.params);
                return await mainBrain.embed(text);
            } catch (fallbackErr) {
                console.error('Fallback to MainBrain for embedding failed:', fallbackErr.message);
                throw err; // Re-throw original error if fallback also fails
            }
        }
    }

    async send(endpoint, body) {
        const url = new URL(endpoint, this.url);
        let method = 'POST';
        let headers = new Headers();
        const request = new Request(url, { method, headers, body: JSON.stringify(body) });
        let data = null;
        try {
            const res = await fetch(request);
            if (res.ok) {
                data = await res.json();
            } else {
                throw new Error(`Ollama Status: ${res.status}`);
            }
        } catch (err) {
            // Only log if it's not a connection error, or log a concise message
            if (err.code === 'ECONNREFUSED') {
                // Silently ignore connection refused as we have fallbacks
            } else {
                console.error(`Ollama request failed: ${err.message}`);
            }
        }
        return data;
    }

    async sendVisionRequest(messages, systemMessage, imageBuffer) {
        const imageMessages = [...messages];
        imageMessages.push({
            role: "user",
            content: [
                { type: "text", text: systemMessage },
                {
                    type: "image_url",
                    image_url: {
                        url: `data:image/jpeg;base64,${imageBuffer.toString('base64')}`
                    }
                }
            ]
        });
        
        return this.sendRequest(imageMessages, systemMessage);
    }
}
