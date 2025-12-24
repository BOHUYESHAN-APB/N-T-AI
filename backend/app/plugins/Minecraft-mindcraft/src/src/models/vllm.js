// This code uses Dashscope and HTTP to ensure the latest support for the Qwen model.
// Qwen is also compatible with the OpenAI API format;

import OpenAIApi from 'openai';
import { getKey, hasKey } from '../utils/keys.js';
import { strictFormat } from '../utils/text.js';

export class VLLM {
    static prefix = 'vllm';
    constructor(model_name, url) {
        this.model_name = model_name;

        let vllm_config = {};
        // 优先使用传入的 url，否则尝试环境变量，最后回退到本地默认
        vllm_config.baseURL = url || process.env.VLLM_BASE_URL || 'http://127.0.0.1:8000/v1';
        vllm_config.apiKey = process.env.VLLM_API_KEY || "sk-vllm-internal";

        this.vllm = new OpenAIApi(vllm_config);
    }

    async sendRequest(turns, systemMessage, stop_seq = '***') {
        let messages = [{ 'role': 'system', 'content': systemMessage }].concat(turns);
        let model = this.model_name || process.env.VLLM_MODEL || "deepseek-ai/DeepSeek-R1-Distill-Qwen-32B";  
        
        if (model.includes('deepseek') || model.includes('qwen')) {
            messages = strictFormat(messages);
        } 

        const pack = {
            model: model,
            messages,
            stop: stop_seq,
        };

        let res = null;
        try {
            console.log(`Awaiting VLLM (${model}) response...`);
            let completion = await this.vllm.chat.completions.create(pack);
            if (completion.choices[0].finish_reason == 'length')
                throw new Error('Context length exceeded');
            console.log('Received.');
            res = completion.choices[0].message.content;
        }
        catch (err) {
            if ((err.message == 'Context length exceeded' || err.code == 'context_length_exceeded') && turns.length > 1) {
                console.log('Context length exceeded, trying again with shorter context.');
                return await this.sendRequest(turns.slice(1), systemMessage, stop_seq);
            } else {
                console.error('VLLM Error:', err.message);
                res = 'My brain disconnected, try again.';
            }
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

    async saveToFile(logFile, logEntry) {
        let task_id = this.agent.task.task_id;
        console.log(task_id)
        let logDir;
        if (this.task_id === null) {
            logDir = path.join(__dirname, `../../bots/${this.agent.name}/logs`);
        } else {
            logDir = path.join(__dirname, `../../bots/${this.agent.name}/logs/${task_id}`);
        }

        await fs.mkdir(logDir, { recursive: true });

        logFile = path.join(logDir, logFile);
        await fs.appendFile(logFile, String(logEntry), 'utf-8');
    }

}