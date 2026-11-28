const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs/promises');const path=require('node:path');
const {savedToken,parseQuota,fetchQuota}=require('../src/huggingface');
const fixture=require('../../Tests/PulseTests/Fixtures/hugging-face-zero-gpu-quota.json');
test('ZeroGPU reports used GPU time and the stated reset',()=>{
 const w=parseQuota(fixture).windows[0];assert.equal(w.usedPercent,40);assert.equal(w.reset,'2025-08-31T18:00:00.000Z');assert.equal(w.reportsLength,false);
 const empty=parseQuota({base:600,current:0,resetsAt:1756663200}).windows[0];assert.equal(empty.usedPercent,100);assert.equal(empty.exhausted,true);assert.equal(empty.reset,'2025-08-31T18:00:00.000Z');
 for(const bad of [{base:0,current:0},{base:1},{base:true,current:1},{base:1,current:-1},[]])assert.throws(()=>parseQuota(bad));
});
test('a pasted Hugging Face token takes precedence over the local login',async()=>{
 const root='E:/WorkSpace/CodexData/TaskTemp';await fs.mkdir(root,{recursive:true});const home=await fs.mkdtemp(path.join(root,'hf-test-'));try{
 const folder=path.join(home,'.cache','huggingface');await fs.mkdir(folder,{recursive:true});await fs.writeFile(path.join(folder,'token'),'"hf_saved"\nother');assert.equal(await savedToken(home),'hf_saved');
 const calls=[];const transport=async(url,headers)=>{calls.push({url,headers});return fixture};await fetchQuota('hf_manual',transport,home);await fetchQuota('',transport,home);
 assert.equal(calls[0].headers.Authorization,'Bearer hf_manual');assert.equal(calls[1].headers.Authorization,'Bearer hf_saved');assert.ok(calls.every(c=>new URL(c.url).host==='huggingface.co'));
 await assert.rejects(fetchQuota('',async()=>{throw Object.assign(new Error('refused'),{status:401})},home),/本地登录已过期/);
 }finally{await fs.rm(home,{recursive:true,force:true})}
});
