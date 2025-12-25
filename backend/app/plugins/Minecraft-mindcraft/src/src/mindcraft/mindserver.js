import { Server } from 'socket.io';
import express from 'express';
import http from 'http';
import path from 'path';
import { fileURLToPath } from 'url';
import * as mindcraft from './mindcraft.js';
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from 'fs';
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const PROFILES_DIR = path.join(__dirname, '../../profiles');
if (!existsSync(PROFILES_DIR)) {
    mkdirSync(PROFILES_DIR, { recursive: true });
}

// Mindserver is:
// - central hub for communication between all agent processes
// - api to control from other languages and remote users 
// - host for webapp

let io;
let server;
const agent_connections = {};
const agent_listeners = [];

const settings_spec = JSON.parse(readFileSync(path.join(__dirname, 'public/settings_spec.json'), 'utf8'));

class AgentConnection {
    constructor(settings, viewer_port) {
        this.socket = null;
        this.settings = settings;
        this.in_game = false;
        this.full_state = null;
        this.viewer_port = viewer_port;
    }
    setSettings(settings) {
        this.settings = settings;
    }
}

let current_settings = {};

export function setCurrentSettings(settings) {
    current_settings = settings;
}

export function registerAgent(settings, viewer_port) {
    let agentConnection = new AgentConnection(settings, viewer_port);
    agent_connections[settings.profile.name] = agentConnection;
}

export function logoutAgent(agentName) {
    if (agent_connections[agentName]) {
        agent_connections[agentName].in_game = false;
        agentsStatusUpdate();
    }
}

    // Initialize the server
export function createMindServer(host_public = false, port = 8080) {
    const app = express();
    server = http.createServer(app);
    io = new Server(server, {
        cors: {
            origin: "*",
            methods: ["GET", "POST"]
        }
    });

    // Ensure port is a number
    const portNum = parseInt(port, 10) || 8080;

    // Serve static files
    const __dirname = path.dirname(fileURLToPath(import.meta.url));
    app.use(express.static(path.join(__dirname, 'public')));

    // Health check route
    app.get('/health', (req, res) => res.json({ status: 'ok', port: portNum }));
    app.get('/ping', (req, res) => res.send('pong'));

    // Config endpoint for UI
    app.get('/config', (req, res) => {
        res.json({
            mindserver_port: portNum,
            current_settings: current_settings
        });
    });

    // Socket.io connection handling
    io.on('connection', (socket) => {
        let curAgentName = null;
        console.log('Client connected');

        agentsStatusUpdate(socket);

        socket.on('get-current-settings', (callback) => {
            callback(current_settings);
        });

        socket.on('update-global-settings', (newSettings, callback) => {
            try {
                Object.assign(current_settings, newSettings);
                const settingsPath = path.join(__dirname, '../../settings.json');
                writeFileSync(settingsPath, JSON.stringify(current_settings, null, 4));
                console.log('Global settings updated and saved.');
                callback({ success: true });
            } catch (err) {
                callback({ success: false, error: err.message });
            }
        });

        socket.on('list-profiles', (callback) => {
            try {
                const files = readdirSync(PROFILES_DIR)
                    .filter(f => f.endsWith('.json'))
                    .map(f => f.replace('.json', ''));
                callback({ success: true, profiles: files });
            } catch (err) {
                callback({ success: false, error: err.message });
            }
        });

        socket.on('upload-profile', (data, callback) => {
            try {
                const { name, content } = data;
                if (!name || !content) {
                    return callback({ success: false, error: 'Name and content are required' });
                }
                const fileName = name.endsWith('.json') ? name : `${name}.json`;
                const filePath = path.join(PROFILES_DIR, fileName);
                
                writeFileSync(filePath, JSON.stringify(content, null, 4));
                console.log(`Profile saved: ${filePath}`);
                callback({ success: true, fileName: fileName });
            } catch (err) {
                callback({ success: false, error: err.message });
            }
        });

        socket.on('get-profile', (name, callback) => {
            try {
                const fileName = name.endsWith('.json') ? name : `${name}.json`;
                const filePath = path.join(PROFILES_DIR, fileName);
                if (!existsSync(filePath)) {
                    return callback({ success: false, error: 'Profile not found' });
                }
                const content = JSON.parse(readFileSync(filePath, 'utf8'));
                callback({ success: true, content: content });
            } catch (err) {
                callback({ success: false, error: err.message });
            }
        });

        socket.on('create-agent', async (settings, callback) => {
            console.log('API create agent...');
            for (let key in settings_spec) {
                if (!(key in settings)) {
                    if (settings_spec[key].required) {
                        callback({ success: false, error: `Setting ${key} is required` });
                        return;
                    }
                    else {
                        settings[key] = settings_spec[key].default;
                    }
                }
            }
            for (let key in settings) {
                if (!(key in settings_spec)) {
                    delete settings[key];
                }
            }
            if (settings.profile?.name) {
                if (settings.profile.name in agent_connections) {
                    callback({ success: false, error: 'Agent already exists' });
                    return;
                }
                let returned = await mindcraft.createAgent(settings);
                callback({ success: returned.success, error: returned.error });
                let name = settings.profile.name;
                if (!returned.success && agent_connections[name]) {
                    mindcraft.destroyAgent(name);
                    delete agent_connections[name];
                }
                agentsStatusUpdate();
            }
            else {
                console.error('Agent name is required in profile');
                callback({ success: false, error: 'Agent name is required in profile' });
            }
        });

        socket.on('get-settings', (agentName, callback) => {
            if (agent_connections[agentName]) {
                callback({ settings: agent_connections[agentName].settings });
            } else {
                callback({ error: `Agent '${agentName}' not found.` });
            }
        });

        socket.on('connect-agent-process', (agentName) => {
            if (agent_connections[agentName]) {
                agent_connections[agentName].socket = socket;
                agentsStatusUpdate();
            }
        });

        socket.on('login-agent', (agentName) => {
            if (agent_connections[agentName]) {
                agent_connections[agentName].socket = socket;
                agent_connections[agentName].in_game = true;
                curAgentName = agentName;
                agentsStatusUpdate();
            }
            else {
                console.warn(`Unregistered agent ${agentName} tried to login`);
            }
        });

        socket.on('disconnect', () => {
            if (agent_connections[curAgentName]) {
                console.log(`Agent ${curAgentName} disconnected`);
                agent_connections[curAgentName].in_game = false;
                agent_connections[curAgentName].socket = null;
                agentsStatusUpdate();
            }
            if (agent_listeners.includes(socket)) {
                removeListener(socket);
            }
        });

        socket.on('chat-message', (agentName, json) => {
            if (!agent_connections[agentName]) {
                console.warn(`Agent ${agentName} tried to send a message but is not logged in`);
                return;
            }
            console.log(`${curAgentName} sending message to ${agentName}: ${json.message}`);
            if (agent_connections[agentName].socket)
                agent_connections[agentName].socket.emit('chat-message', curAgentName, json);
        });

        socket.on('set-agent-settings', (agentName, settings) => {
            const agent = agent_connections[agentName];
            if (agent) {
                agent.setSettings(settings);
                if (agent.socket)
                    agent.socket.emit('restart-agent');
            }
        });

        socket.on('restart-agent', (agentName) => {
            if (!agentName) {
                // 如果没有提供名字，尝试重启当前连接的所有 agent
                console.log('Restarting all agents');
                for (let name in agent_connections) {
                    if (agent_connections[name].socket)
                        agent_connections[name].socket.emit('restart-agent');
                }
                return;
            }
            console.log(`Restarting agent: ${agentName}`);
            if (agent_connections[agentName] && agent_connections[agentName].socket)
                agent_connections[agentName].socket.emit('restart-agent');
        });

        socket.on('stop-agent', (agentName) => {
            mindcraft.stopAgent(agentName);
        });

        socket.on('start-agent', (agentName) => {
            mindcraft.startAgent(agentName);
        });

        socket.on('destroy-agent', (agentName) => {
            if (agent_connections[agentName]) {
                mindcraft.destroyAgent(agentName);
                delete agent_connections[agentName];
            }
            agentsStatusUpdate();
        });

        socket.on('stop-all-agents', () => {
            console.log('Killing all agents');
            for (let agentName in agent_connections) {
                mindcraft.stopAgent(agentName);
            }
        });

        socket.on('shutdown', () => {
            console.log('Shutting down');
            for (let agentName in agent_connections) {
                mindcraft.stopAgent(agentName);
            }
            // wait 2 seconds
            setTimeout(() => {
                console.log('Exiting MindServer');
                process.exit(0);
            }, 2000);
            
        });

		socket.on('send-message', (agentName, data) => {
			if (!agent_connections[agentName]) {
				console.warn(`Agent ${agentName} not in game, cannot send message via MindServer.`);
				return
			}
			try {
				agent_connections[agentName].socket.emit('send-message', data)
			} catch (error) {
				console.error('Error: ', error);
			}
		});

        socket.on('bot-output', (agentName, message) => {
            console.log(`[BOT_OUTPUT] ${JSON.stringify({ agentName, message })}`);
            
            // 检查是否包含 Microsoft 认证信息
            if (message.includes('Microsoft Auth Required')) {
                const match = message.match(/Go to (.*?) and enter code: (.*)/);
                if (match) {
                    const data = {
                        username: agentName,
                        verification_uri: match[1],
                        user_code: match[2]
                    };
                    io.emit('ms-auth-code', data);
                }
            }
            
            io.emit('bot-output', agentName, message);
        });

        socket.on('listen-to-agents', () => {
            addListener(socket);
        });
    });

    let host = host_public ? '0.0.0.0' : 'localhost';
    console.log(`Attempting to start MindServer on ${host}:${portNum}...`);
    
    server.on('error', (err) => {
        if (err.code === 'EADDRINUSE') {
            console.error(`ERROR: Port ${portNum} is already in use. Please choose a different port in the plugin settings.`);
        } else {
            console.error(`MindServer error:`, err);
        }
    });

    server.listen(portNum, host, () => {
        const addr = server.address();
        console.log(`MindServer is successfully running on http://${addr.address}:${addr.port}`);
        console.log(`Management UI available at http://${host === '0.0.0.0' ? 'localhost' : host}:${portNum}`);
    });

    return server;
}

function agentsStatusUpdate(socket) {
    if (!socket) {
        socket = io;
    }
    let agents = [];
    for (let agentName in agent_connections) {
        const conn = agent_connections[agentName];
        agents.push({
            name: agentName, 
            in_game: conn.in_game,
            viewerPort: conn.viewer_port,
            socket_connected: !!conn.socket
        });
    };
    socket.emit('agents-status', agents);
}


let listenerInterval = null;
function addListener(listener_socket) {
    agent_listeners.push(listener_socket);
    if (agent_listeners.length === 1) {
        listenerInterval = setInterval(async () => {
            const states = {};
            for (let agentName in agent_connections) {
                let agent = agent_connections[agentName];
                if (agent.in_game) {
                    try {
                        const state = await new Promise((resolve) => {
                            agent.socket.emit('get-full-state', (s) => resolve(s));
                        });
                        states[agentName] = state;
                    } catch (e) {
                        states[agentName] = { error: String(e) };
                    }
                }
            }
            for (let listener of agent_listeners) {
                listener.emit('state-update', states);
            }
        }, 1000);
    }
}

function removeListener(listener_socket) {
    agent_listeners.splice(agent_listeners.indexOf(listener_socket), 1);
    if (agent_listeners.length === 0) {
        clearInterval(listenerInterval);
        listenerInterval = null;
    }
}

// Optional: export these if you need access to them from other files
export const getIO = () => io;
export const getServer = () => server;
export const numStateListeners = () => agent_listeners.length;