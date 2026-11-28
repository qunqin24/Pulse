const test=require('node:test');const assert=require('node:assert/strict');const {atlas,neuralwatt}=require('../src/energy-providers');const {fetchProvider}=require('../src/providers');
const fixture=name=>require('../../Tests/PulseTests/Fixtures/'+name+'.json');
test('Atlas Cloud validates the account and currency while preserving debt',()=>{
 assert.deepEqual(atlas(fixture('atlas-cloud-balance')),{windows:[],balances:[{currency:'USD',amount:42.5}]});assert.equal(atlas({object:'balance',scope:'account',available:{value:'-3.25',currency:'usd'}}).balances[0].amount,-3.25);
 for(const bad of [{object:'balance',scope:'team',available:{value:'1',currency:'usd'}},{object:'balance',scope:'account',available:{value:1,currency:'usd'}},{object:'balance',scope:'account',available:{value:'1',currency:'dollars'}}])assert.throws(()=>atlas(bad));
});
test('Neuralwatt separates energy, key allowance and prepaid balance',()=>{
 const r=neuralwatt(fixture('neuralwatt-quota'));assert.equal(r.windows.length,2);assert.equal(r.windows[0].usedPercent,25);assert.equal(r.windows[0].reportsLength,true);assert.equal(r.windows[1].usedPercent,25);assert.equal(r.balances[0].amount,51);assert.equal(r.plan,'Pro');
 const d=neuralwatt({balance:{total_credits_usd:10,credits_used_usd:2},subscription:{kwh_used:1,kwh_remaining:3}});assert.equal(d.windows[0].usedPercent,25);assert.equal(d.balances[0].amount,8);
 assert.throws(()=>neuralwatt({balance:{credits_remaining_usd:'51'}}));assert.throws(()=>neuralwatt({balance:{},subscription:{kwh_included:0,kwh_used:1}}));
});
test('each provider sends credentials only to its own endpoint',async()=>{
 for(const [id,host,name] of [['atlas','api.atlascloud.ai','atlas-cloud-balance'],['neuralwatt','api.neuralwatt.com','neuralwatt-quota']]){await fetchProvider(id,'sample',async(url,headers)=>{assert.equal(new URL(url).host,host);assert.equal(headers.Authorization,'Bearer sample');return fixture(name)});await assert.rejects(fetchProvider(id,'',async()=>{throw Error('unexpected')}),/密钥/);}
});
