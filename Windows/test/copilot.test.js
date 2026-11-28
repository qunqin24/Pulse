const test=require('node:test');const assert=require('node:assert/strict');const {parseCopilot,fetchCopilot}=require('../src/copilot');
const fixture=name=>require('../../Tests/PulseTests/Fixtures/copilot-'+name+'.json');
test('Copilot quotas invert remaining and preserve each reported lane',()=>{
 const r=parseCopilot(fixture('normal'));assert.deepEqual(r.windows.map(w=>w.scope),['Premium requests','Chat','Completions']);assert.deepEqual(r.windows.map(w=>w.usedPercent),[30,10,5]);assert.equal(r.plan,'Individual');assert.equal(r.windows[0].reset,'2026-10-01T00:00:00.000Z');
 assert.deepEqual(parseCopilot(fixture('unissued-and-spent')).windows.map(w=>w.scope),['Chat']);const business=parseCopilot(fixture('business-token-billing')).windows[0];assert.equal(business.exhausted,true);assert.deepEqual(business.amounts,{used:40000,remaining:0,limit:40000});
 const overage=parseCopilot(fixture('overage')).windows[0];assert.equal(overage.usedPercent,100);assert.equal(overage.exhausted,false);
});
test('Copilot sends its own OAuth token using the editor request format',async()=>{
 const r=await fetchCopilot('token-example',async(url,headers)=>{assert.equal(url,'https://api.github.com/copilot_internal/user');assert.equal(headers.Authorization,'token token-example');assert.equal(headers['Editor-Version'],'vscode/1.96.2');return fixture('normal')});assert.equal(r.windows.length,3);await assert.rejects(fetchCopilot('',async()=>{throw Error('unexpected')}),/登录/);
});
