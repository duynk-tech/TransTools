import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
const source = readFileSync(new URL('./page/probe.js', import.meta.url), 'utf8');
function host(translator) {
  const elements = new Map();
  const get = id => { if (!elements.has(id)) elements.set(id,{value:'',textContent:'',disabled:false}); return elements.get(id); };
  get('direction').value='en-vi'; get('input').value='PRIVATE TEST INPUT';
  const context = {document:{getElementById:get},navigator:{userAgent:'test-runtime',onLine:false},isSecureContext:true,performance,AbortController,Date,JSON,console,addEventListener(){},setTimeout};
  if(translator) context.Translator=translator;
  vm.runInNewContext(source,context);
  return get;
}
test('absent API is reported instead of attempting a network fallback',async()=>{
  const get=host(); await get('check').onclick(); await get('translate').onclick();
  const report=JSON.parse(get('evidence').textContent);
  assert.equal(report.checks.at(-1).error,'api-absent'); assert.equal(report.offlineVerified,false);
});
test('successful local result does not leak text into evidence or claim offline verification',async()=>{
  let destroyed=false;
  const get=host({availability:async()=> 'available',create:async()=>({translate:async()=> 'PRIVATE TRANSLATION',destroy(){destroyed=true;}})});
  await get('translate').onclick();
  assert.equal(get('result').textContent,'PRIVATE TRANSLATION'); assert.equal(destroyed,true);
  assert.equal(get('translate').disabled,false); assert.equal(get('cancel').disabled,true);
  assert.ok(!get('evidence').textContent.includes('PRIVATE')); assert.equal(JSON.parse(get('evidence').textContent).offlineVerified,false);
});
test('cancel releases the session and permits retry',async()=>{
  let destroyed=false;
  const get=host({create:async()=>({translate:(_text,{signal})=>new Promise((_resolve,reject)=>{signal.addEventListener('abort',()=>reject(new Error('cancelled')));}),destroy(){destroyed=true;}}),availability:async()=> 'available'});
  const pending=get('translate').onclick(); await new Promise(resolve=>setImmediate(resolve)); get('cancel').onclick(); await pending;
  assert.equal(destroyed,true); assert.equal(get('translate').disabled,false);
  assert.match(JSON.parse(get('evidence').textContent).checks.at(-1).error,/cancelled/);
});
