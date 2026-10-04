import { put, list } from '@vercel/blob';
import { readFile, stat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
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
async function sha256(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}
async function main() {
  const version = validateVersion((process.env.RELEASE_VERSION || '').replace(/^v/, ''));
  if (!process.env.BLOB_READ_WRITE_TOKEN) throw new Error('BLOB_READ_WRITE_TOKEN is required');
  const { blobs } = await list({ prefix: 'updates/latest.json', limit: 10 });
  const pointer = blobs.find(blob => blob.pathname === 'updates/latest.json');
  if (pointer) {
    const response = await fetch(pointer.url);
    if (!response.ok) throw new Error('Unable to read current release');
    const current = await response.json();
    if (compareVersions(version, validateVersion(current.version)) <= 0) {
      throw new Error('Refusing to overwrite or downgrade an already published release');
    }
  }
  const assets = {};
  for (const extension of ['zip', 'dmg']) {
    const file = `build/TransTools.${extension}`;
    const digest = await sha256(file);
    const size = (await stat(file)).size;
    const uploaded = await put(`releases/v${version}/TransTools.${extension}`, createReadStream(file), {
      access: 'public', addRandomSuffix: false, allowOverwrite: false,
      contentType: 'application/octet-stream', multipart: true,
      cacheControlMaxAge: 31536000
    });
    assets[extension] = { url: uploaded.url, sha256: digest, size };
    await put(`releases/v${version}/TransTools.${extension}.sha256`, `${digest}  TransTools.${extension}\n`, {
      access: 'public', addRandomSuffix: false, allowOverwrite: false, contentType: 'text/plain'
    });
    console.log(`Uploaded TransTools.${extension}`);
  }

  // Windows assets (if built)
  const windowsAssets = [
    { key: 'installer', paths: ['windows/build/TransTools-Setup.exe', 'build/TransTools-Setup.exe'], targetName: 'TransTools-Setup.exe' },
    { key: 'exe', paths: ['windows/build/TransTools.exe', 'build/TransTools.exe'], targetName: 'TransTools.exe' },
    { key: 'windowsZip', paths: ['windows/build/TransTools-Windows-Portable.zip', 'build/TransTools-Windows-Portable.zip'], targetName: 'TransTools-Windows-Portable.zip' }
  ];

  for (const item of windowsAssets) {
    let sourcePath = item.paths.find(p => {
      try { return stat(p).then(() => true).catch(() => false); } catch { return false; }
    });
    // synchronous check with async stat
    for (const p of item.paths) {
      try {
        await stat(p);
        sourcePath = p;
        break;
      } catch {}
    }

    if (sourcePath) {
      const digest = await sha256(sourcePath);
      const size = (await stat(sourcePath)).size;
      const uploaded = await put(`releases/v${version}/${item.targetName}`, createReadStream(sourcePath), {
        access: 'public', addRandomSuffix: false, allowOverwrite: false,
        contentType: 'application/octet-stream', multipart: true,
        cacheControlMaxAge: 31536000
      });
      assets[item.key] = { url: uploaded.url, sha256: digest, size };
      await put(`releases/v${version}/${item.targetName}.sha256`, `${digest}  ${item.targetName}\n`, {
        access: 'public', addRandomSuffix: false, allowOverwrite: false, contentType: 'text/plain'
      });
      console.log(`Uploaded ${item.targetName} for Windows to Vercel Blob`);
    }
  }
  let notes = `Trans Tools v${version}: cải tiến và sửa lỗi.`;
  if (process.env.RELEASE_NOTES_FILE) {
    try { notes = await readFile(process.env.RELEASE_NOTES_FILE, 'utf8'); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  const release = {
    schemaVersion: 1, version, title: `Trans Tools v${version}`, notes,
    publishedAt: new Date().toISOString(), minimumMacOS: '14.0',
    releaseURL: 'https://trans-tools.vercel.app/releases', ...assets
  };
  const data = JSON.stringify(release, null, 2);
  await put(`releases/v${version}/manifest.json`, data, {
    access: 'public', addRandomSuffix: false, allowOverwrite: false, contentType: 'application/json'
  });
  await put('updates/latest.json', data, {
    access: 'public', addRandomSuffix: false, allowOverwrite: true,
    contentType: 'application/json', cacheControlMaxAge: 60
  });
  console.log(`Published v${version}`);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
