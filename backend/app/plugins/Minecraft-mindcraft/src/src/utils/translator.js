import translate from 'google-translate-api-x';
import settings from '../agent/settings.js';

// Disable SSL verification for translation requests globally to avoid fetch failures
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

export async function handleTranslation(message) {
    let preferred_lang = String(settings.language).toLowerCase();
    if (!preferred_lang || preferred_lang === 'en' || preferred_lang === 'english')
        return message;
    
    // Map 'zh' to 'zh-CN' as google-translate-api-x may not support plain 'zh'
    if (preferred_lang === 'zh') preferred_lang = 'zh-CN';
    
    try {
        console.log(`[Translator] Translating to ${preferred_lang}: ${message.substring(0, 30)}...`);
        const translation = await translate(message, { to: preferred_lang });
        return translation.text || message;
    } catch (error) {
        console.error(`[Translator] Error translating to ${preferred_lang}:`, error.message);
        return message;
    }
}

export async function handleEnglishTranslation(message) {
    let preferred_lang = String(settings.language).toLowerCase();
    if (!preferred_lang || preferred_lang === 'en' || preferred_lang === 'english')
        return message;
    try {
        console.log(`[Translator] Translating to English: ${message.substring(0, 30)}...`);
        const translation = await translate(message, { to: 'en' }); // use 'en' instead of 'english'
        return translation.text || message;
    } catch (error) {
        console.error('[Translator] Error translating to English:', error.message);
        return message;
    }
}
