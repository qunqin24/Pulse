const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {parseMoonshot,fetchMoonshot}=require('../src/moonshot');
const fixture=JSON.parse(fs.readFileSync(path.join(__dirname,'../../Tests/PulseTests/Fixtures/moonshot-balance.json'),'utf8'));
test('Moonshot retains the reported balance and the region currency',()=>{
 assert.deepEqual(parseMoonshot(fixture,'USD'),{windows:[],balances:[{currency:'USD',amount:49.58}]});
 assert.equal(parseMoonshot({code:0,status:true,data:{available_balance:-2}},'CNY').balances[0].amount,-2);
 for(const bad of [{code:1,status:true,data:{available_balance:2}},{code:0,status:true,data:{available_balance:'2'}},{code:0,data:{available_balance:2}}])assert.throws(()=>parseMoonshot(bad,'USD'));
});
test('Moonshot falls back only on refusal and remembers the accepted region',async()=>{
 const calls=[];const transport=async(url,headers)=>{calls.push({url,headers});if(url.includes('.ai/'))throw Object.assign(new Error('refused'),{status:401});return fixture;};
 assert.equal((await fetchMoonshot('cn-test-distinct',transport)).balances[0].currency,'CNY');
 assert.deepEqual(calls.map(x=>new URL(x.url).host),['api.moonshot.ai','api.moonshot.cn']);
 assert.ok(calls.every(x=>x.headers.Authorization==='Bearer cn-test-distinct'));
 calls.length=0;await fetchMoonshot('cn-test-distinct',transport);assert.deepEqual(calls.map(x=>new URL(x.url).host),['api.moonshot.cn']);
 let count=0;await assert.rejects(fetchMoonshot('network-test',async()=>{count++;throw new Error('network');}),/network/);assert.equal(count,1);
});
