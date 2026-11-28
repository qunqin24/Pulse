const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
const {deepinfra,vercel}=require('../src/profile-parsers');const {fetchProvider}=require('../src/providers');
const fixture=name=>JSON.parse(fs.readFileSync(path.join(__dirname,'../../Tests/PulseTests/Fixtures',name+'.json'),'utf8'));
test('DeepInfra shows the inverted ledger alongside a reported spend limit',()=>{
 const reading=deepinfra(fixture('deepinfra-checklist'));assert.ok(Math.abs(reading.balances[0].amount-95.81)<1e-8);assert.equal(reading.balances[0].currency,'USD');assert.ok(Math.abs(reading.windows[0].usedPercent-19.7)<1e-8);assert.equal(reading.windows[0].reportsLength,false);
 assert.deepEqual(deepinfra({stripe_balance:2.75,recent:7,limit:-1}),{windows:[],balances:[{currency:'USD',amount:-9.75}]});
 assert.equal(deepinfra({stripe_balance:0,recent:-1}).balances[0].amount,0);assert.throws(()=>deepinfra({stripe_balance:'5',recent:1}));assert.throws(()=>deepinfra({stripe_balance:1}));
});
test('Vercel reads only finite decimal string balances including debt',()=>{
 assert.deepEqual(vercel(fixture('vercel-ai-gateway-credits')),{windows:[],balances:[{currency:'USD',amount:95.5}]});assert.equal(vercel({balance:'-2.25'}).balances[0].amount,-2.25);
 for(const balance of [95.5,'','0x10','NaN','Infinity'])assert.throws(()=>vercel({balance}));
});
test('new providers send their own key only to the corresponding endpoint',async()=>{
 for(const [id,host,reply] of [['deepinfra','api.deepinfra.com',fixture('deepinfra-checklist')],['vercel','ai-gateway.vercel.sh',fixture('vercel-ai-gateway-credits')]]){
  let calls=0;const result=await fetchProvider(id,'test-key',async(url,headers)=>{calls++;assert.equal(new URL(url).host,host);assert.equal(headers.Authorization,'Bearer test-key');return reply;});assert.equal(calls,1);assert.equal(result.balances[0].currency,'USD');
  await assert.rejects(fetchProvider(id,'',async()=>{throw new Error('should not call');}),/密钥/);
 }
});
