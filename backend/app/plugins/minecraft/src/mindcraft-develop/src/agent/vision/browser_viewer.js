import settings from '../settings.js';

export async function addBrowserViewer(bot, count_id) {
    if (settings.render_bot_view) {
        try {
            const prismarineViewer = (await import('prismarine-viewer')).default;
            const mineflayerViewer = prismarineViewer.mineflayer;
            mineflayerViewer(bot, { port: 3000+count_id, firstPerson: true, });
        } catch (err) {
            console.warn('Failed to initialize browser viewer:', err.message);
        }
    }
}