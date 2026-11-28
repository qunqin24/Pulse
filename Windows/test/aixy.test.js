const test=require('node:test');const assert=require('node:assert/strict');const {parseAixy}=require('../src/aixy');const {fetchProvider}=require('../src/providers');const fixture=require('../../Tests/PulseTests/Fixtures/aixy-usage.json');
test('Aixy keeps the binding budget for each period',()=>{
 const w=parseAixy(fixture).windows;assert.deepEqual(w.map(x=>x.id),['aixy.b_key_daily','aixy.b_project_monthly','aixy.b_lifetime']);assert.deepEqual(w.map(x=>x.usedPercent),[30,25,12.5]);assert.equal(w[0].reset,'2026-09-21T00:00:00.000Z');assert.equal(w[1].reportsLength,false);assert.equal(w[2].reset,null);
 assert.throws(()=>parseAixy({object:'key.usage',currency:'EUR',key:{id:'k'},budgets:[]}));assert.throws(()=>parseAixy({object:'key.usage',currency:'USD',key:{id:'k'},budgets:[]}));
});
test('Aixy sends its key only to the gateway endpoint',async()=>{
 const r=await fetchProvider('aixy','abc',async(url,headers)=>{assert.equal(url,'https://api.aixy-gateway.com/v1/usage');assert.equal(headers.Authorization,'Bearer abc');return fixture});assert.equal(r.windows.length,3);await assert.rejects(fetchProvider('aixy','',async()=>{throw Error('unexpected')}),/密钥/);
});
