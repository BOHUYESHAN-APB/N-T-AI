import { Camera } from './camera.js';

export class POVStreamer {
    constructor(agent) {
        this.agent = agent;
        this.camera = null;
        this.interval = null;
        this.fps = process.env.MC_POV_FPS ? parseInt(process.env.MC_POV_FPS) : 10; // 提升至 10 FPS 或环境变量设置
        this.quality = process.env.MC_POV_QUALITY ? parseFloat(process.env.MC_POV_QUALITY) : 0.6; // 压缩质量
        this.backendUrl = process.env.NTAI_BACKEND_URL;
    }

    async start() {
        if (!this.backendUrl) {
            console.warn('NTAI_BACKEND_URL not set, POV streaming disabled');
            return;
        }

        const fp = './bots/' + this.agent.name + '/screenshots/';
        this.camera = new Camera(this.agent.bot, fp);

        // 等待相机就绪
        this.camera.on('ready', () => {
            console.log(`[POV Streamer] Camera ready for ${this.agent.name}, starting stream...`);
            this.interval = setInterval(async () => {
                await this.sendFrame();
            }, 1000 / this.fps);
        });
    }

    async sendFrame() {
        if (!this.camera || !this.camera.enabled) return;

        try {
            const bot = this.agent.bot;
            const stats = {
                health: bot.health,
                food: bot.food,
                oxygen: bot.oxygenLevel,
                pos: bot.entity?.position,
                heldItem: bot.heldItem ? bot.heldItem.name : 'None'
            };

            const base64Image = await this.captureBase64();
            if (!base64Image) return;

            // 发送到后端
            await fetch(`${this.backendUrl}/plugins/minecraft/pov`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    agent: this.agent.name,
                    image: base64Image,
                    stats: stats
                })
            }).catch(() => {});
        } catch (err) {
        }
    }

    async captureBase64() {
        if (!this.camera.enabled) return null;
        
        try {
            const bot = this.agent.bot;
            if (!bot.entity) return null;

            const center = {
                x: bot.entity.position.x,
                y: bot.entity.position.y + bot.entity.height,
                z: bot.entity.position.z
            };

            this.camera.viewer.camera.position.set(center.x, center.y, center.z);
            await this.camera.worldView.updatePosition(center);
            this.camera.viewer.setFirstPersonCamera(bot.entity.position, bot.entity.yaw, bot.entity.pitch);
            this.camera.viewer.update();
            this.camera.renderer.render(this.camera.viewer.scene, this.camera.viewer.camera);

            // 直接从 canvas 获取 base64
            const buffer = this.camera.canvas.toBuffer('image/jpeg', { quality: this.quality });
            return buffer.toString('base64');
        } catch (err) {
            return null;
        }
    }

    stop() {
        if (this.interval) {
            clearInterval(this.interval);
            this.interval = null;
        }
    }
}
