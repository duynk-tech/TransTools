import { latestRelease } from '../lib/update-feed.js';
export default async function handler(req, res) {
  if (!['GET', 'HEAD'].includes(req.method)) return res.status(405).end();
  try {
    const release = await latestRelease();
    if (!release) return res.status(404).json({ error: 'No published release' });
    const format = req.query.format;
    let targetUrl;
    if (format === 'exe') {
      targetUrl = release.installer?.url || release.exe?.url;
    } else if (format === 'winzip') {
      targetUrl = release.windowsZip?.url || release.exe?.url;
    } else if (format === 'zip') {
      targetUrl = release.zip?.url;
    } else {
      targetUrl = release.dmg?.url;
    }

    if (!targetUrl) return res.status(404).json({ error: 'Requested format not available for this release' });
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Location', targetUrl);
    return res.status(302).end();
  } catch {
    return res.status(503).json({ error: 'Download service temporarily unavailable' });
  }
}
