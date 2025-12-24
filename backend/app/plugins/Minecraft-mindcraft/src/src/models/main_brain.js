import OpenAIApi from 'openai';
import { getKey, hasKey } from '../utils/keys.js';
import { strictFormat } from '../utils/text.js';

/**
 * MainBrain model class that proxies requests to the N-T-AI backend.
 * This allows the Minecraft agent to reuse the main brain's configuration and vision capabilities.
 */
export class MainBrain {
    static prefix = 'main-brain';
    static _embeddingCache = new Map(); // 静态缓存，所有实例共享

    constructor(model_name, url, params) {
        this.model_name = model_name;
        this.params = params;

        let config = {
            // Default to the N-T-AI backend URL if not provided
            baseURL: url || process.env.NTAI_BACKEND_URL || 'http://127.0.0.1:23456/v1',
            apiKey: getKey('OPENAI_API_KEY') || 'sk-ntai-internal'
        };

        this.openai = new OpenAIApi(config);
    }

    async sendRequest(turns, systemMessage, stop_seq = '***') {
        let messages = [{ 'role': 'system', 'content': systemMessage }].concat(turns);
        messages = strictFormat(messages);

        const pack = {
            model: this.model_name || "default", // Backend will use its default model if "default"
            messages,
            stop: stop_seq,
            ...(this.params || {})
        };

        let res = null;
        try {
            console.log('Awaiting Main Brain response...');
            let completion = await this.openai.chat.completions.create(pack);
            console.log('Received.');
            res = completion.choices[0].message.content;
        }
        catch (err) {
            console.error('Main Brain Error:', err.message);
            // Return a special error object instead of a string to avoid accidental chatting
            res = { error: true, message: 'Main Brain connection lost', details: err.message };
        }
        return res;
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
        try {
            const embedding = await this.openai.embeddings.create({
                model: "default",
                input: text,
            });
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
