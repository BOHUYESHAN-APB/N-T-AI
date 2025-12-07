import { Redis } from '@upstash/redis';

const redis = new Redis({
  url: process.env.UPSTASH_REDIS_REST_URL,
  token: process.env.UPSTASH_REDIS_REST_TOKEN,
});

export default async function handler(req, res) {
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const exclude = req.query.exclude;
    const ids = await redis.smembers('peers:set');
    const list = [];
    for (const id of ids) {
      if (id === exclude) continue;
      const key = `peers:data:${id}`;
      const raw = await redis.get(key);
      if (!raw) {
        // expired — remove from set
        await redis.srem('peers:set', id);
        continue;
      }
      try {
        const info = JSON.parse(raw);
        list.push({ peerId: id, ...info });
      } catch (e) {
        // malformed, skip
      }
    }
    return res.json({ peers: list });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'internal_error', detail: String(err) });
  }
}
