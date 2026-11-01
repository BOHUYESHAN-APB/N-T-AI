import * as Mindcraft from './src/mindcraft/mindcraft.js';
import settings from './settings.js';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import { readFileSync } from 'fs';

function parseArguments() {
    return yargs(hideBin(process.argv))
        .option('profiles', {
            type: 'array',
            describe: 'List of agent profile paths',
        })
        .option('task_path', {
            type: 'string',
            describe: 'Path to task file to execute'
        })
        .option('task_id', {
            type: 'string',
            describe: 'Task ID to execute'
        })
        .help()
        .alias('help', 'h')
        .parse();
}
const args = parseArguments();
if (args.profiles) {
    settings.profiles = args.profiles;
}
if (args.task_path) {
    let tasks = JSON.parse(readFileSync(args.task_path, 'utf8'));
    if (args.task_id) {
        settings.task = tasks[args.task_id];
        settings.task.task_id = args.task_id;
    }
    else {
        throw new Error('task_id is required when task_path is provided');
    }
}

// these environment variables override certain settings
if (process.env.MINECRAFT_PORT) {
    settings.port = process.env.MINECRAFT_PORT;
}
if (process.env.MINDSERVER_PORT) {
    settings.mindserver_port = process.env.MINDSERVER_PORT;
}
if (process.env.PROFILES && JSON.parse(process.env.PROFILES).length > 0) {
    settings.profiles = JSON.parse(process.env.PROFILES);
}
if (process.env.INSECURE_CODING) {
    settings.allow_insecure_coding = true;
}
if (process.env.BLOCKED_ACTIONS) {
    settings.blocked_actions = JSON.parse(process.env.BLOCKED_ACTIONS);
}
if (process.env.MAX_MESSAGES) {
    settings.max_messages = process.env.MAX_MESSAGES;
}
if (process.env.NUM_EXAMPLES) {
    settings.num_examples = process.env.NUM_EXAMPLES;
}
if (process.env.LOG_ALL) {
    settings.log_all_prompts = process.env.LOG_ALL;
}

async function main() {
    await Mindcraft.init(true, settings.mindserver_port, settings.auto_open_ui, settings);

    for (let profile_path of settings.profiles) {
        try {
            // 为每个 agent 创建独立的配置副本
            const agent_settings = JSON.parse(JSON.stringify(settings));
            
            // 从路径中读取真实的 profile 内容
            const profile = JSON.parse(readFileSync(profile_path, 'utf8'));
            agent_settings.profile = profile;

            // 只有当设置了 agent_name 时才覆盖，否则保持 profile 原名
            if (settings.agent_name) {
                console.log(`Overriding profile name ${profile.name} with agent_name from settings: ${settings.agent_name}`);
                agent_settings.profile.name = settings.agent_name;
            }

            console.log(`Creating agent: ${agent_settings.profile.name} with model: ${agent_settings.agent_model || profile.model}`);
            await Mindcraft.createAgent(agent_settings);
        } catch (err) {
            console.error(`Failed to load profile ${profile_path}:`, err);
        }
    }
    console.log("Finished starting agents from profiles.");
}

main().catch(err => {
    console.error('Fatal error in main:', err);
});

// 优雅退出处理
function shutdown() {
    console.log("Shutting down MindCraft...");
    process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

// 当父进程（Python）断开连接时自动退出
process.stdin.on('end', () => {
    console.log("Parent process disconnected, exiting...");
    shutdown();
});
process.stdin.resume(); // 确保 stdin 保持打开状态以检测关闭事件