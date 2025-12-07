import { Redis } from '@upstash/redis';

const redis = new Redis({
  url: process.env.UPSTASH_REDIS_REST_URL,
  token: process.env.UPSTASH_REDIS_REST_TOKEN,
});

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { peerId, addr = null, meta = {} } = req.body || {};
    if (!peerId) return res.status(400).json({ error: 'peerId required' });

    const now = Date.now();
    const key = `peers:data:${peerId}`;
    // Store peer data with TTL (5 minutes)
    await redis.set(key, JSON.stringify({ addr, meta, updatedAt: now }), { ex: 300 });
    // Ensure peerId exists in set for listing
    await redis.sadd('peers:set', peerId);

    return res.json({ ok: true, peerId, updatedAt: now });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'internal_error', detail: String(err) });
  }
}
