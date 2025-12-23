import settings from '../agent/settings.js';
import OpenAI from 'openai';

let openaiInstance = null;

function getOpenAI() {
    if (openaiInstance) return openaiInstance;
    
    const backendUrl = process.env.NTAI_BACKEND_URL;
    if (!backendUrl) {
        return null;
    }
    
    openaiInstance = new OpenAI({
        baseURL: backendUrl,
        apiKey: 'sk-ntai-internal', // 内部调用，使用占位符
    });
    return openaiInstance;
}

async function llmTranslate(text, to_lang) {
    const openai = getOpenAI();
    if (!openai) {
        console.warn('NTAI_BACKEND_URL not set or OpenAI initialization failed, skipping LLM translation');
        return text;
    }
    
    try {
        const response = await openai.chat.completions.create({
            model: "default",
            messages: [
                { 
                    role: "system", 
                    content: `You are a professional translator. Translate the following text to ${to_lang}. Respond ONLY with the translated text, no extra commentary.` 
                },
                { role: "user", content: text }
            ],
            temperature: 0
        });
        
        const translation = response.choices[0].message.content.trim();
        return translation || text;
    } catch (error) {
        console.error('LLM Translation error:', error);
        return text;
    }
}

export async function handleTranslation(message) {
    let preferred_lang = String(settings.language).toLowerCase();
    if (!preferred_lang || preferred_lang === 'en' || preferred_lang === 'english')
        return message;
    
    console.log(`Translating to ${preferred_lang} using LLM...`);
    return await llmTranslate(message, preferred_lang);
}

export async function handleEnglishTranslation(message) {
    // 如果已经是英文或者没设置语言，直接返回
    // 注意：这里我们假设 handleEnglishTranslation 是为了把其他语言转成英文
    // 逻辑上如果当前是英文环境，则不需要翻译
    let preferred_lang = String(settings.language).toLowerCase();
    if (!preferred_lang || preferred_lang === 'en' || preferred_lang === 'english')
        return message;

    console.log(`Translating to English using LLM...`);
    return await llmTranslate(message, 'English');
}
