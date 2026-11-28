const test=require('node:test');const assert=require('node:assert/strict');const {parseVenice}=require('../src/venice');const {fetchProvider}=require('../src/providers');const fixture=require('../../Tests/PulseTests/Fixtures/venice-balance.json');
test('Venice respects the consumption currency and does not turn DIEM into a quota',()=>{
 assert.deepEqual(parseVenice(fixture),{windows:[],balances:[{currency:'USD',amount:25.75}]});
 assert.deepEqual(parseVenice({canConsume:true,consumptionCurrency:'DIEM',balances:{diem:'90.50',usd:'25.75'}}),{windows:[],displayBalance:{amount:90.5,unit:'DIEM'}});
 assert.deepEqual(parseVenice({canConsume:false,balances:{diem:3,usd:null}}),{windows:[],displayBalance:{amount:3,unit:'DIEM'}});
 for(const v of [{},{canConsume:'yes',balances:{usd:1}},{canConsume:true,balances:{usd:true}},{canConsume:true,balances:{usd:'0x10'}},{canConsume:true,balances:{usd:'',diem:null}}])assert.throws(()=>parseVenice(v));
});
test('Venice uses its own endpoint and refuses a missing key',async()=>{
 const result=await fetchProvider('venice',' key ',async(url,headers)=>{assert.equal(url,'https://api.venice.ai/api/v1/billing/balance');assert.equal(headers.Authorization,'Bearer key');return {canConsume:true,consumptionCurrency:'DIEM',balances:{diem:20}}});assert.equal(result.displayBalance.unit,'DIEM');
 await assert.rejects(fetchProvider('venice','',async()=>{throw Error('unexpected')}),/密钥/);
});
