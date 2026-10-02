import { list } from '@vercel/blob';

export async function latestRelease() {
  const { blobs } = await list({ prefix: 'updates/latest.json', limit: 10 });
  const entry = blobs.find(blob => blob.pathname === 'updates/latest.json');
  if (!entry) return null;
  const response = await fetch(entry.url, { signal: AbortSignal.timeout(10000) });
  if (!response.ok) throw new Error('Manifest unavailable');
  const release = await response.json();
  if (release.schemaVersion !== 1 || !release.zip || !release.dmg) throw new Error('Invalid manifest');
  return release;
}
