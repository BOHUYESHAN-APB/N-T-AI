# N-T-AI — P2P 聊天与笔记（项目骨架）

简要说明
----------

N-T-AI 旨在做一个去中心化优先的聊天与笔记应用（PC + Android），并提供用户可选择的自托管引导/信令服务器（bootstrap server）以提升 P2P 连接的可靠性。本仓库包含最小骨架与多种部署选项：本地 Docker 服务与 Vercel Serverless 模板，便于不同用户场景。

核心理念
----------
- P2P 为主：消息优先点对点传输、端到端加密、最小化中心化依赖；
- 用户自托管：提供可选的 bootstrap/signaling server（Docker 或 Vercel 模板），用户可选择自行部署；
- 跨平台复用：最大化使用 TypeScript + React 以便 Electron（桌面）与 React Native（移动）间复用逻辑；
- 可扩展：模块化 packages（p2p、crypto、core、ui），便于替换底层 transport 或升级群聊协议（如引入 MLS）。

仓库主要内容
----------------

- `docker/bootstrap-server/` — 轻量 Node.js 引导/信令服务器模板（REST API），用于开发与自托管；包含 `Dockerfile` 与使用说明；
- `vercel/bootstrap-server/` — 可直接部署在 Vercel 的 serverless 版本（基于 Upstash Redis），便于用户一键部署；
- `packages/desktop/` — Electron 最小 demo（演示如何向 bootstrap server 报到）；
- `packages/p2p/` — P2P 网络层说明与起始模板（后续将实现 simple-peer/libp2p 适配器）；
- `tarot_prompts.md` — 先前为塔罗功能准备的 79 条二次元图像提示词（将用于后续的卡面生成）。

快速开始（本地，Docker 版 bootstrap server）
-------------------------------------------------

1. 启动引导服务器（在一个终端）:

```powershell
cd docker/bootstrap-server
docker build -t ntai-bootstrap-server .
docker run -p 3000:3000 ntai-bootstrap-server
```

2. 运行桌面 demo（另一个终端）:

```powershell
cd packages/desktop
npm install
npx electron .
```

3. 在桌面 demo 页面点击 “Announce to bootstrap server” 将向 `http://localhost:3000/announce` 发送注册请求；后续 `packages/p2p` 会实现发现并建立 P2P 数据通道。

Vercel 一键部署（serverless 引导服务）
--------------------------------------

如果你希望快速部署一个无状态的引导服务，可使用 `vercel/bootstrap-server` 目录并结合 Upstash Redis：

- 在 Upstash 创建 Redis，记录 REST URL 与 Token；
- 将本仓库（或仅此目录）部署到 Vercel，填写环境变量 `UPSTASH_REDIS_REST_URL` 与 `UPSTASH_REDIS_REST_TOKEN`；
- README 中已包含一个 Vercel "Deploy" 按钮模板，替换为你真实的 GitHub 仓库即可实现一键部署。

项目许可与商业授权（重要，请阅读）
----------------------------------

本项目默认采用 GPLv3 许可证（见仓库根 `LICENSE`）。GPLv3 允许第三方以 GPL 兼容方式使用、修改和分发本项目的源代码，包括商业用途。这意味着如果你只把代码放在 GPL 下，其他方仍可能在 GPL 条款下用于商业目的。

若你希望“禁止他人商用”或在商业场景中保留权益，常见做法是采用“二重授权 / dual-licensing”策略：

1. 将开源版本以 GPLv3 发布（对开源社区友好）；
2. 同时为商业用户提供单独的商业授权（proprietary commercial license），明确商业使用需获得授权并支付许可费用；

本仓库包含 `COMMERCIAL_LICENSE.md`（模板与说明），说明如何联系项目拥有者以获取商业许可。注意：如果你的目标是严格禁止任何商业使用，则应改用带 “Non-Commercial” 限制的许可证（例如 CC BY-NC 家族或自定义不可商用条款），但那会使项目不再被视为自由/开源（并限制贡献者和生态）。

如果你希望我替你：
- 把仓库标注为 “GPLv3 OR commercial license” 的二重授权格式（我会添加示范文字）；或
- 换成不可商用的许可证（我会把具体许可证文本与影响写清楚，并添加 `LICENSE`），

请告诉我你的偏好（二选一），我会把对应许可证文件写入仓库并更新 README 中的说明。

贡献指南
---------

欢迎贡献。建议流程：

1. Fork 仓库并在 feature 分支上实现；
2. 运行现有 demo 与 bootstrap server 进行本地验证；
3. 提交 PR 并在描述中说明变更点与测试步骤；

安全与隐私提示
----------------

- 本仓库提供的 bootstrap/signaling server 仅用于引导/发现，不应在生产中直接用于消息中继或存储敏感数据；
- 在生产部署时请启用 TLS、认证、速率限制与日志审计；
- 群聊安全（回放保护、前向保密/向后保密）需要更复杂的协议（如 MLS），目前项目为 MVP 阶段采用简化群密钥方案，后续可升级。

下一步计划（我将继续）
--------------------

- 在 `packages/p2p` 实现 simple-peer + HTTP signaling 的最小原型，并让 Electron demo 能够发现 peers 并建立加密数据通道；
- 增加 `packages/crypto`（libsodium 封装）和 `packages/core`（消息模型与本地存储接口）；
- 根据你选择的许可策略，添加或替换 `LICENSE` 与 `COMMERCIAL_LICENSE.md` 文件。

---

如需我现在把许可改为“禁止商用”的不可商用许可证，或设置为二重授权（GPL + 商业授权），请回复你的选择；我会接着把许可文件和 README 里的说明替换/补全。
