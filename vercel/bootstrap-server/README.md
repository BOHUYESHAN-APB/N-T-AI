# Vercel: Bootstrap / Signaling Server (Serverless)

说明：此目录包含可部署到 Vercel 的 serverless 版本引导/信令接口，使用 Upstash Redis 作为持久化后端（适配无状态 serverless 环境）。

优点：
- 无需用户自行维护持续运行的节点进程，Vercel 可快速部署；
- 使用 Upstash Redis（或其它托管 Redis）保存 peer 信息与过期策略，保证 serverless 环境下的发现功能可用；

环境变量（必填）:
- `UPSTASH_REDIS_REST_URL` — Upstash Redis REST URL
- `UPSTASH_REDIS_REST_TOKEN` — Upstash Redis REST Token

部署步骤（快速）:

1. 在 Upstash 控制台创建 Redis 实例，记录 REST URL 与 Token；
2. 将本仓库连接到 Vercel（或把此目录作为单独仓库）；
3. 在 Vercel 项目设置中添加上面两个环境变量；
4. 在 Vercel 上选择部署（使用默认构建），函数会出现在 `/api/announce` 和 `/api/peers`；

接口：
- POST /api/announce  { peerId, addr?, meta? }  — 通知服务器自己的存在（TTL 默认 5 分钟）
- GET  /api/peers     ?exclude=<peerId>          — 获取当前注册的 peers（会过滤已过期的条目）

注意事项与生产建议：
- 当前实现为最小模板：生产请启用 HTTPS（Vercel 默认启用）、对 API 添加认证/速率限制、并监控成本；
- Upstash 免费层适合测试；若用户不愿使用 Upstash，可在 README 中提供改用 Supabase/Managed Redis/自托管 Redis 的说明；
- 如果项目需要 WebSocket 或 TURN 中继，Vercel serverless 并不适合长期 socket 连接；TURN 服务仍需要第三方或自托管。

一键部署思路：
- 可在 README 顶部放置 Vercel “Deploy” 按钮（需要把该目录作为公开 Github 仓库或提供 Vercel 模板），并在仓库中提供 `.vercel` 配置模板与清晰的 env 说明，用户点击后能快速完成部署与 env 填写。

## 一键部署（Deploy to Vercel）

点击下面的按钮可以快速在 Vercel 上创建并部署本目录为一个 Serverless 项目。请替换链接中的 `USERNAME/REPO` 为你的 GitHub 仓库地址，或在 Vercel 导入页面将 "Root Directory" 设置为 `vercel/bootstrap-server`。

[![Deploy to Vercel](https://vercel.com/button)](https://vercel.com/new/git/external?repository-url=https://github.com/USERNAME/REPO&project-name=ntai-bootstrap-server)

部署后记得在 Vercel 项目设置中添加以下环境变量（Environment Variables）：

- `UPSTASH_REDIS_REST_URL` — Upstash Redis REST URL
- `UPSTASH_REDIS_REST_TOKEN` — Upstash Redis REST Token

如果你希望我把 README 中的按钮改为指向具体仓库（我可以替你替换为真实的 GitHub URL），把仓库的远程地址发给我或授权我使用它，我会替换链接以实现真·一键部署。
