# packages/p2p — P2P 网络层（说明 & 起始模板）

目标：封装 P2P 发现、信令、WebRTC 传输与重连逻辑，供 `desktop` 与 `mobile` 使用。

建议实现要点：
- 使用 libp2p-js 在 Node / Electron 环境中提供 DHT / rendezvous / relay 支持；
- 在 React Native 中若 libp2p-js 无法直接运行，使用 `react-native-webrtc` + 自有 signaling 层（对接 `docker/bootstrap-server`）；
- 抽象出通用接口：createNode(config) 返回 node 对象（on('peer', ...), connect(peerId), send(peerId, data) 等）。

示例：在完成阶段会在此目录放置 TypeScript 实现文件 `src/index.ts`，目前为占位说明文档。
