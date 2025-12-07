# Bootstrap / Signaling Server (轻量模板)

用途：用于节点注册与发现（信令），不持久化消息，仅做引导与短期信令交换。用户可自行托管以提高 P2P 连接成功率。

快速使用（Docker）：

```powershell
# 在仓库根目录下
cd docker/bootstrap-server
docker build -t ntai-bootstrap-server .
docker run -p 3000:3000 ntai-bootstrap-server
```

REST 接口：
- POST /announce  { peerId, addr?, meta? }
- GET  /peers     ?exclude=<peerId>

注意：此实现为最简模板，仅用于开发与自托管测试。生产环境请加认证、TLS、持久化和限流。
