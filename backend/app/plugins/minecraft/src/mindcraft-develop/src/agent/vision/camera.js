import THREE from 'three';
import fs from 'fs/promises';
import { Vec3 } from 'vec3';
import { EventEmitter } from 'events';

import worker_threads from 'worker_threads';
global.Worker = worker_threads.Worker;


export class Camera extends EventEmitter {
    constructor (bot, fp) {
        super();
        this.bot = bot;
        this.fp = fp;
        this.viewDistance = 12;
        this.width = 800;
        this.height = 512;
        this.canvas = null;
        this.renderer = null;
        this.viewer = null;
        this.enabled = false;

        this._init().then(() => {
            if (this.enabled) {
                this.emit('ready');
            }
        }).catch(err => {
            console.warn('Camera initialization failed:', err.message);
        });
    }
  
    async _init () {
        try {
            const { createCanvas } = await import('node-canvas-webgl/lib/index.js');
            const { Viewer } = await import('prismarine-viewer/viewer/lib/viewer.js');
            
            this.canvas = createCanvas(this.width, this.height);
            this.renderer = new THREE.WebGLRenderer({ canvas: this.canvas });
            this.viewer = new Viewer(this.renderer);
            this.enabled = true;

            const botPos = this.bot.entity.position;
            const center = new Vec3(botPos.x, botPos.y+this.bot.entity.height, botPos.z);
            this.viewer.setVersion(this.bot.version);
            // Load world
            const { WorldView } = await import('prismarine-viewer/viewer/lib/worldView.js');
            const worldView = new WorldView(this.bot.world, this.viewDistance, center);
            this.viewer.listen(worldView);
            worldView.listenToBot(this.bot);
            await worldView.init(center);
            this.worldView = worldView;
        } catch (err) {
            this.enabled = false;
            console.warn('Could not initialize Camera (vision will be disabled):', err.message);
            if (err.message.includes('canvas')) {
                console.warn('Tip: This usually means the "canvas" native module is missing or failed to compile on your system.');
            }
        }
    }
  
    async capture() {
        if (!this.enabled) {
            return "Camera is disabled because of missing dependencies (canvas).";
        }
        const center = new Vec3(this.bot.entity.position.x, this.bot.entity.position.y+this.bot.entity.height, this.bot.entity.position.z);
        this.viewer.camera.position.set(center.x, center.y, center.z);
        await this.worldView.updatePosition(center);
        this.viewer.setFirstPersonCamera(this.bot.entity.position, this.bot.entity.yaw, this.bot.entity.pitch);
        this.viewer.update();
        this.renderer.render(this.viewer.scene, this.viewer.camera);

        const imageStream = this.canvas.createJPEGStream({
            bufsize: 4096,
            quality: 100,
            progressive: false
        });
        
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const filename = `screenshot_${timestamp}`;

        const { getBufferFromStream } = await import('prismarine-viewer/viewer/lib/simpleUtils.js');
        const buf = await getBufferFromStream(imageStream);
        await this._ensureScreenshotDirectory();
        await fs.writeFile(`${this.fp}/${filename}.jpg`, buf);
        console.log('saved', filename);
        return filename;
    }

    async _ensureScreenshotDirectory() {
        let stats;
        try {
            stats = await fs.stat(this.fp);
        } catch (e) {
            if (!stats?.isDirectory()) {
                await fs.mkdir(this.fp);
            }
        }
    }
}
  
