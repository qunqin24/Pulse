// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
const CLIENT='Iv1.b507a08c87ecfe98';
const clampInterval=n=>Math.min(60,Math.max(1,Number.isFinite(n)?Math.floor(n):5));
async function start(post,signal){
 const reply=await post('https://github.com/login/device/code',{client_id:CLIENT,scope:'read:user'},signal);
 if(typeof reply.user_code!=='string'||!/^[-A-Z0-9]{4,32}$/.test(reply.user_code)||typeof reply.device_code!=='string'||!reply.device_code||reply.verification_uri!=='https://github.com/login/device')throw new Error('GitHub 返回了无法读取的授权信息');
 return {userCode:reply.user_code,deviceCode:reply.device_code,interval:clampInterval(reply.interval),expiresIn:Math.min(900,Math.max(1,Number.isFinite(reply.expires_in)?reply.expires_in:900))};
}
function sleep(ms,signal){return new Promise((resolve,reject)=>{if(signal.aborted)return reject(new Error('登录已取消'));const timer=setTimeout(done,ms);function done(){signal.removeEventListener('abort',cancel);resolve();}function cancel(){clearTimeout(timer);signal.removeEventListener('abort',cancel);reject(new Error('登录已取消'));}signal.addEventListener('abort',cancel,{once:true});});}
async function poll(prompt,post,signal,{wait=sleep,now=Date.now}={}){
 const deadline=now()+prompt.expiresIn*1000;let interval=prompt.interval;
 while(now()<deadline){await wait(Math.min(interval*1000,Math.max(0,deadline-now())),signal);if(signal.aborted)throw new Error('登录已取消');if(now()>=deadline)break;
  const r=await post('https://github.com/login/oauth/access_token',{client_id:CLIENT,device_code:prompt.deviceCode,grant_type:'urn:ietf:params:oauth:grant-type:device_code'},signal);
  if(signal.aborted)throw new Error('登录已取消');if(typeof r.access_token==='string'&&r.access_token.trim())return r.access_token.trim();
  if(r.error==='authorization_pending'||r.error==null)continue;if(r.error==='slow_down'){interval=clampInterval(Number.isFinite(r.interval)?r.interval:interval+5);continue;}
  if(r.error==='access_denied')throw new Error('GitHub 登录已拒绝');if(r.error==='expired_token')throw new Error('GitHub 登录代码已过期');throw new Error('GitHub 登录失败');
 }
 throw new Error('GitHub 登录代码已过期');
}
module.exports={start,poll};
