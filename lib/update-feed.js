
const repository = 'duynk-tech/TransTools';
export async function githubRelease(fetcher = fetch) {
  const response = await fetcher(`https://api.github.com/repos/${repository}/releases/latest`, {
    headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'TransTools-Update-Service' },
    signal: AbortSignal.timeout(10000)
  });
  if (!response.ok) throw new Error('Release source unavailable');
  const release = await response.json();
  const version = String(release.tag_name || '').replace(/^v/, '');
  if (release.draft || release.prerelease || !/^\d+\.\d+\.\d+$/.test(version)) throw new Error('Invalid release');
  const prefix = `https://github.com/${repository}/releases/download/v${version}/`;
  async function asset(name, required = false) {
    const item = release.assets?.find(a => a.name === name);
    if (!item) { if (required) throw new Error('Missing release asset'); return undefined; }
    if (item.browser_download_url !== prefix + name || !(item.size > 0)) throw new Error('Invalid release asset');
    let sha256 = item.digest?.match(/^sha256:([a-f0-9]{64})$/i)?.[1];
    if (!sha256 && required) {
      const checksum = release.assets.find(a => a.name === `${name}.sha256`);
      if (checksum?.browser_download_url !== prefix + `${name}.sha256`) throw new Error('Missing checksum');
      const result = await fetcher(checksum.browser_download_url, { signal: AbortSignal.timeout(10000) });
      if (!result.ok) throw new Error('Checksum unavailable');
      const match = (await result.text()).trim().match(/^([a-f0-9]{64})\s+\*?([^\r\n]+)$/i);
      if (!match || match[2] !== name) throw new Error('Invalid checksum');
      sha256 = match[1];
    }
    return { url: item.browser_download_url, size: item.size, sha256: sha256 || '' };
  }
  return {
    schemaVersion: 1, version, title: release.name || `Trans Tools v${version}`,
    notes: release.body || '', publishedAt: release.published_at,
    releaseURL: 'https://trans-tools.vercel.app/releases',
    zip: await asset('TransTools.zip', true), dmg: await asset('TransTools.dmg', true),
    installer: await asset('TransTools-Setup.exe'), windowsZip: await asset('TransTools-Windows-Portable.zip')
  };
}

export async function latestRelease() {
  return githubRelease();
}
