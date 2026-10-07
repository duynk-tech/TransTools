import { stat } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export function validateVersion(version) {
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('Release version must be x.y.z');
  return version;
}
export function compareVersions(a, b) {
  const x = a.split('.').map(Number), y = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return Math.sign(x[i] - y[i]);
  return 0;
}
export async function firstExistingFile(paths) {
  for (const path of paths) {
    try { if ((await stat(path)).isFile()) return path; }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  return undefined;
}

// Kept for compatibility with existing release validation imports.
// Installer publication is exclusively handled by GitHub Releases.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.error('Vercel installer uploads are disabled. Publish installers through the GitHub release workflow.');
  process.exitCode = 1;
}
