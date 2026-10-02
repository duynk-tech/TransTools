import { latestRelease } from '../lib/update-feed.js';
export default async function handler(req, res) {
  if (!['GET', 'HEAD'].includes(req.method)) return res.status(405).end();
  try {
    const release = await latestRelease();
    if (!release) return res.status(404).json({ error: 'No published release' });
    res.setHeader('Cache-Control', 'public, max-age=0, s-maxage=30');
    return res.status(200).json(release);
  } catch {
    return res.status(503).json({ error: 'Update service temporarily unavailable' });
  }
}
