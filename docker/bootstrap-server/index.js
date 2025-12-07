const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(bodyParser.json({ limit: '1mb' }));

// Simple in-memory peer registry: { peerId: { addr, meta, updatedAt } }
const peers = new Map();

// Announce or update your presence
app.post('/announce', (req, res) => {
  const { peerId, addr, meta } = req.body || {};
  if (!peerId) return res.status(400).json({ error: 'peerId required' });
  peers.set(peerId, { addr: addr || null, meta: meta || {}, updatedAt: Date.now() });
  return res.json({ ok: true });
});

// Get peers (optionally exclude own peerId)
app.get('/peers', (req, res) => {
  const exclude = req.query.exclude;
  const list = [];
  for (const [id, info] of peers.entries()) {
    if (id === exclude) continue;
    list.push({ peerId: id, ...info });
  }
  return res.json({ peers: list });
});

// Simple cleanup: remove peers not updated in N ms
const STALE_MS = 1000 * 60 * 5; // 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [id, info] of peers.entries()) {
    if (now - info.updatedAt > STALE_MS) peers.delete(id);
  }
}, 60_000);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Bootstrap server listening on port ${PORT}`);
});
