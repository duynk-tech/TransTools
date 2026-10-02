import test from 'node:test';
import assert from 'node:assert/strict';
import { validateVersion, compareVersions } from '../scripts/publish-vercel-release.mjs';
test('only stable numeric release versions', () => {
 assert.equal(validateVersion('1.3.1'),'1.3.1');
 for(const version of ['v1.3.1','../latest','1.3.1-beta','1.3']) assert.throws(()=>validateVersion(version));
});
test('numeric ordering prevents stale releases and downgrades', () => {
 assert.equal(compareVersions('1.10.0','1.9.9'),1);
 assert.equal(compareVersions('1.3.1','1.3.1'),0);
 assert.equal(compareVersions('1.3.0','1.3.1'),-1);
});
