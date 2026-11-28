const test=require('node:test');const assert=require('node:assert/strict');const device=require('../src/github-device');
test('GitHub device login requests the narrow scope and validates the verification address',async()=>{
 const post=async(url,body)=>{assert.equal(url,'https://github.com/login/device/code');assert.equal(body.scope,'read:user');return {user_code:'ABCD-1234',device_code:'secret',verification_uri:'https://github.com/login/device',interval:5,expires_in:900}};
 const p=await device.start(post,new AbortController().signal);assert.equal(p.userCode,'ABCD-1234');await assert.rejects(device.start(async()=>({user_code:'ABCD-1234',device_code:'s',verification_uri:'https://evil.example'}),new AbortController().signal));
});
test('polling honors pending, slow down, cancellation, and does not return a late token',async()=>{
 let time=0,round=0;const waits=[];const controller=new AbortController();const token=await device.poll({deviceCode:'secret',interval:2,expiresIn:100},async()=>[ {error:'authorization_pending'},{error:'slow_down',interval:10},{access_token:'token'}][round++],controller.signal,{now:()=>time,wait:async(ms)=>{waits.push(ms);time+=ms}});assert.equal(token,'token');assert.deepEqual(waits,[2000,2000,10000]);
 const stopped=new AbortController();stopped.abort();await assert.rejects(device.poll({deviceCode:'s',interval:1,expiresIn:10},async()=>({access_token:'late'}),stopped.signal,{now:()=>0,wait:async()=>{}}),/取消/);
});
