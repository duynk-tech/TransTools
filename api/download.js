import { latestRelease } from '../lib/update-feed.js';
export default async function handler(req, res) {
  if (!['GET', 'HEAD'].includes(req.method)) return res.status(405).end();
  try {
    const release = await latestRelease();
    if (!release) return res.status(404).json({ error: 'No published release' });
    const format = req.query.format === 'zip' ? 'zip' : 'dmg';
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Location', release[format].url);
    return res.status(302).end();
  } catch {
    return res.status(503).json({ error: 'Download service temporarily unavailable' });
  }
}
