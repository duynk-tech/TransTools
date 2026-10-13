import test from 'node:test';
import assert from 'node:assert/strict';
import { validateVersion, compareVersions, firstExistingFile } from '../scripts/publish-vercel-release.mjs';
test('only stable numeric release versions', () => {
 assert.equal(validateVersion('1.3.1'),'1.3.1');
 for(const version of ['v1.3.1','../latest','1.3.1-beta','1.3']) assert.throws(()=>validateVersion(version));
});
test('numeric ordering prevents stale releases and downgrades', () => {
 assert.equal(compareVersions('1.10.0','1.9.9'),1);
 assert.equal(compareVersions('1.3.1','1.3.1'),0);
 assert.equal(compareVersions('1.3.0','1.3.1'),-1);
});

import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
test('optional Windows assets skip missing paths and choose an existing file', async () => {
 const dir = await mkdtemp(join(tmpdir(), 'trans-tools-release-'));
 try {
  const missing = join(dir, 'missing.exe'), present = join(dir, 'present.exe');
  assert.equal(await firstExistingFile([missing]), undefined);
  await writeFile(present, 'test asset');
  assert.equal(await firstExistingFile([missing, present]), present);
  assert.equal(await firstExistingFile([dir, present]), present);
 } finally { await rm(dir, { recursive: true, force: true }); }
});

import { githubRelease } from '../lib/update-feed.js';
test('GitHub fallback requires stable release and trusted assets with checksums', async () => {
 const makeRelease = () => ({ tag_name: 'v1.4.2', published_at: '2026-10-05T00:00:00Z', assets: ['TransTools.zip','TransTools.dmg'].map(name => ({ name, size: 12, digest: 'sha256:' + 'a'.repeat(64), browser_download_url: `https://github.com/duynk-tech/TransTools/releases/download/v1.4.2/${name}` })) });
 const fetcher = release => async () => ({ ok: true, json: async () => release });
 const good = await githubRelease(fetcher(makeRelease()));
 assert.equal(good.version, '1.4.2'); assert.equal(good.zip.sha256.length, 64);
 const bad = makeRelease(); bad.assets[0].browser_download_url = 'https://example.com/file.zip';
 await assert.rejects(githubRelease(fetcher(bad)), /Invalid release asset/);
 const preview = makeRelease(); preview.prerelease = true;
 await assert.rejects(githubRelease(fetcher(preview)), /Invalid release/);
 const missing = makeRelease(); delete missing.assets[0].digest;
 await assert.rejects(githubRelease(fetcher(missing)), /Missing checksum/);
});
