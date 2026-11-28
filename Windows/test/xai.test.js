const test=require('node:test');const assert=require('node:assert/strict');const {credential,parseBalance,fetchBalance}=require('../src/xai');const fixture=require('../../Tests/PulseTests/Fixtures/xai-api-prepaid-balance.json');
test('xAI posted cent ledger becomes a USD balance',()=>{
 assert.deepEqual(parseBalance(fixture),{windows:[],balances:[{currency:'USD',amount:12.34}]});assert.equal(parseBalance({total:{val:'250'}}).balances[0].amount,-2.5);
 for(const val of ['', '1.2.3','Infinity','1e3',42])assert.throws(()=>parseBalance({total:{val}}));
});
test('xAI validates and escapes the team while sending only the management key',async()=>{
 const auth=credential(' team 1 : key:with:colon ');assert.equal(auth.key,'key:with:colon');assert.equal(auth.encoded,'team%201');
 for(const bad of ['missing',':key','../path:key','..:key','a\\b:key','team:\nkey'])assert.equal(credential(bad),null);
 let count=0;await fetchBalance(' team 1 : key:with:colon ',async(url,headers)=>{count++;assert.equal(url,'https://management-api.x.ai/v1/billing/teams/team%201/prepaid/balance');assert.equal(headers.Authorization,'Bearer key:with:colon');return fixture});assert.equal(count,1);
 await assert.rejects(fetchBalance('invalid',async()=>{throw Error('unexpected')}),/TeamID/);
});
