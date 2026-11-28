const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs/promises');const path=require('node:path');const n=require('../src/nous');
const account=require('../../Tests/PulseTests/Fixtures/nous-portal-account.json');const auth=require('../../Tests/PulseTests/Fixtures/nous-portal-auth.json');
test('Nous account separates the monthly grant and spendable balance',()=>{
 const result=n.parseAccount(account);assert.equal(result.windows[0].usedPercent,75);assert.equal(result.windows[0].reset,'2026-10-12T04:29:00.000Z');assert.equal(result.plan,'Ultra');assert.equal(result.balances[0].amount,74.25);
 assert.equal(n.parseAccount({purchased_credits_remaining:0}).balances[0].amount,0);for(const bad of [{},{purchased_credits_remaining:true},{purchased_credits_remaining:''},{error:'bad'}])assert.throws(()=>n.parseAccount(bad));
});
test('Nous only trusts its HTTPS origin, picks the longest pool token and reads JWT expiry',()=>{
 for(const bad of ['https://evil.example.com','https://notnousresearch.com','http://portal.nousresearch.com','https://portal.nousresearch.com/steal','https://portal.nousresearch.com:443','https://portal.nousresearch.com?x=1'])assert.equal(n.trustedPortal(bad),null);
 assert.equal(n.trustedPortal('https://preview.nousresearch.com/'),'https://preview.nousresearch.com');
 const chosen=n.login({credential_pool:{nous:[{access_token:'old',expires_at:'2026-07-16T09:00:00Z'},{access_token:'new',expires_at:'2026-07-16T12:00:00Z',portal_base_url:'https://evil.example.com'}]}});assert.equal(chosen.token,'new');assert.equal(chosen.portal,'https://portal.nousresearch.com');assert.equal(n.jwtExpiry('e30.eyJleHAiOjE3ODQxOTYwMDB9.sig'),1784196000000);
});
test('Nous skips expired Hermes tokens and never renews them',async()=>{
 const root='E:/WorkSpace/CodexData/TaskTemp';await fs.mkdir(root,{recursive:true});const home=await fs.mkdtemp(path.join(root,'nous-test-'));try{const dir=path.join(home,'.hermes');await fs.mkdir(path.join(dir,'shared'),{recursive:true});await fs.writeFile(path.join(dir,'auth.json'),JSON.stringify(auth));const now=Date.parse('2026-07-16T10:59:30Z');await assert.rejects(n.storedLogin(home,now),/过期/);
 await fs.writeFile(path.join(dir,'shared','nous_auth.json'),JSON.stringify({access_token:'shared',expires_at:'2026-07-16T12:00:00Z'}));const found=await n.storedLogin(home,now);assert.equal(found.token,'shared');let calls=0;await n.fetchNous(async(url,headers)=>{calls++;assert.equal(url,'https://portal.nousresearch.com/api/oauth/account');assert.equal(headers.Authorization,'Bearer shared');return account},home,now);assert.equal(calls,1);
 }finally{await fs.rm(home,{recursive:true,force:true})}
});
