import OpenAIApi from 'openai';
import { getKey, hasKey } from '../utils/keys.js';
import { strictFormat } from '../utils/text.js';
import settings from '../agent/settings.js';

/**
 * MainBrain model class that proxies requests to the N-T-AI backend.
 * This allows the Minecraft agent to reuse the main brain's configuration and vision capabilities.
 */
export class MainBrain {
    static prefix = 'main-brain';
    static _embeddingCache = new Map(); // 静态缓存，所有实例共享

    constructor(model_name, url, params, api_key) {
        this.model_name = model_name;
        this.params = params;

        // Ensure the URL has /v1 if it's pointing to the N-T-AI backend
        let baseURL = url || settings.agent_base_url || process.env.NTAI_BACKEND_URL || 'http://127.0.0.1:23456/v1';
        if (baseURL && !baseURL.endsWith('/v1') && !baseURL.endsWith('/v1/')) {
            baseURL = baseURL.endsWith('/') ? baseURL + 'v1' : baseURL + '/v1';
        }

        let config = {
            baseURL: baseURL,
            apiKey: api_key || settings.agent_api_key || getKey('OPENAI_API_KEY') || 'sk-ntai-internal'
        };

        this.openai = new OpenAIApi(config);
    }

    async sendRequest(turns, systemMessage, stop_seq = '***') {
        let messages = [{ 'role': 'system', 'content': systemMessage }].concat(turns);
        messages = strictFormat(messages);

        const pack = {
            model: this.model_name || settings.agent_model || "default", // Backend will use its default model if "default"
            messages,
            stop: stop_seq,
            user: "minecraft_agent", // 使用专用 ID 隔离 RAG 记忆和历史
            ...(this.params || {})
        };

        const headers = {
            'X-Usage-Type': 'minecraft',
            'X-Target-Api-Key': settings.agent_api_key || '',
            'X-Target-Base-Url': settings.agent_base_url || '',
            'X-Target-Model': settings.agent_model || ''
        };

        let res = null;
        try {
            console.log('Awaiting Main Brain response...');
            let completion = await this.openai.chat.completions.create(pack, { headers });
            console.log('Received.');
            res = completion.choices[0].message.content;
            return res;
        }
        catch (err) {
            console.error('Main Brain Error:', err.message);
            // Return a string instead of an object to prevent crashes in other parts of the code
            return `Error: Main Brain connection lost. Details: ${err.message}`;
        }
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

    async embed(text) {
        if (text.length > 8191)
            text = text.slice(0, 8191);
        
        if (MainBrain._embeddingCache.has(text)) {
            return MainBrain._embeddingCache.get(text);
        }

        console.log(`Embedding text: ${text.substring(0, 50)}...`);
        const headers = {
            'X-Usage-Type': 'minecraft',
            'X-Target-Api-Key': settings.agent_api_key || '',
            'X-Target-Base-Url': settings.agent_base_url || '',
            'X-Target-Model': settings.agent_model || ''
        };

        try {
            const embedding = await this.openai.embeddings.create({
                model: settings.agent_model || "default",
                input: text,
            }, { headers });
            const result = embedding.data[0].embedding;
            MainBrain._embeddingCache.set(text, result);
            console.log(`Embedding complete for: ${text.substring(0, 50)}...`);
            return result;
        } catch (err) {
            console.error(`Embedding error: ${err.message}`);
            throw err;
        }
    }
}
