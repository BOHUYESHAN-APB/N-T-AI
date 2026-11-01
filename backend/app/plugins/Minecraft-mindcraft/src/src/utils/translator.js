import translate from 'google-translate-api-x';
import settings from '../agent/settings.js';
import { MainBrain } from '../models/main_brain.js';

// Disable SSL verification for translation requests globally to avoid fetch failures
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

async function translateByLLM(message, target) {
    try {
        const mb = new MainBrain('main-brain/default', settings.ntai_backend_url, {}, settings.agent_api_key);
        const sys = `Translate the user input into ${target}. Output only the translation.`;
        const turns = [{ role: 'user', content: message }];
        const res = await mb.sendRequest(turns, sys);
        return typeof res === 'string' ? res : message;
    } catch (_) {
        return null;
    }
}

export async function handleTranslation(message) {
    if (settings.translate_in_plugin === false) return message;
    let preferred_lang = String(settings.language).toLowerCase();
    if (!preferred_lang || preferred_lang === 'en' || preferred_lang === 'english')
        return message;
    
    // Map 'zh' to 'zh-CN' as google-translate-api-x may not support plain 'zh'
    if (preferred_lang === 'zh') preferred_lang = 'zh-CN';
    
    try {
        if (settings.translate_use_llm === true) {
            const llm = await translateByLLM(message, preferred_lang);
            if (llm) return llm;
        }
        console.log(`[Translator] Translating to ${preferred_lang}: ${message.substring(0, 30)}...`);
        const translation = await translate(message, { to: preferred_lang });
        return translation.text || message;
    } catch (error) {
        console.error(`[Translator] Error translating to ${preferred_lang}:`, error.message);
        return message;
    }
}

export async function handleEnglishTranslation(message) {
    if (settings.translate_in_plugin === false) return message;
    let preferred_lang = String(settings.language).toLowerCase();
    if (!preferred_lang || preferred_lang === 'en' || preferred_lang === 'english')
        return message;
    try {
        if (settings.translate_use_llm === true) {
            const llm = await translateByLLM(message, 'en');
            if (llm) return llm;
        }
        console.log(`[Translator] Translating to English: ${message.substring(0, 30)}...`);
        const translation = await translate(message, { to: 'en' }); // use 'en' instead of 'english'
        return translation.text || message;
    } catch (error) {
        console.error('[Translator] Error translating to English:', error.message);
        return message;
    }
}
