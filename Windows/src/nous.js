// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os');
const fallback='https://portal.nousresearch.com';
function trustedPortal(raw){
 if(typeof raw!=='string')return null;const text=raw.trim().replace(/\/+$/,'');try{const u=new URL(text);if(!/^https:\/\/[^/?#:@]+$/i.test(text)||u.protocol!=='https:'||!(u.hostname==='nousresearch.com'||u.hostname.endsWith('.nousresearch.com'))||u.username||u.password||u.port||u.pathname!=='/'||u.search||u.hash)return null;return u.origin;}catch{return null;}
}
function jwtExpiry(token){try{const parts=token.split('.');if(parts.length!==3)return null;const exp=JSON.parse(Buffer.from(parts[1],'base64url').toString('utf8')).exp;return typeof exp==='number'&&Number.isFinite(exp)?exp*1000:null;}catch{return null;}}
function entry(state){if(!state||typeof state.access_token!=='string'||!state.access_token.trim())return null;const token=state.access_token.trim(),stamp=typeof state.expires_at==='string'?Date.parse(state.expires_at):NaN;return {token,portal:trustedPortal(state.portal_base_url)??fallback,expiresAt:Number.isFinite(stamp)?stamp:jwtExpiry(token)};}
function login(root){if(!root||typeof root!=='object'||Array.isArray(root))return null;const direct=entry(root.providers?.nous);if(direct)return direct;const pool=root.credential_pool?.nous;if(Array.isArray(pool)){const entries=pool.map(entry).filter(Boolean).sort((a,b)=>(b.expiresAt??-Infinity)-(a.expiresAt??-Infinity));if(entries.length)return entries[0];}return entry(root);}
async function storedLogin(home=os.homedir(),now=Date.now()){
 let expired=false;for(const file of ['auth.json','shared/nous_auth.json']){let found;try{found=login(JSON.parse(await fs.readFile(path.join(home,'.hermes',file),'utf8')));}catch{continue;}if(!found)continue;if(found.expiresAt!==null&&found.expiresAt-now<=60000){expired=true;continue;}return found;}throw new Error(expired?'Hermes 登录已过期，请先运行 Hermes 更新登录':'找不到 Hermes 的 Nous Portal 登录');
}
function parseAccount(root){
 if(!root||typeof root!=='object'||Array.isArray(root))throw new Error('服务商返回了无法读取的数据');if(root.error!=null)throw new Error('服务商返回错误');
 const sub=root.subscription??{},access=root.paid_service_access??{};let malformed=false;
 function amount(value){if(value==null)return null;if(typeof value==='number'&&Number.isFinite(value))return value;if(typeof value==='string'&&/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(value.trim())){const n=Number(value);if(Number.isFinite(n))return n;}malformed=true;return null;}
 const monthly=amount(sub.monthly_credits),remaining=amount(sub.credits_remaining)??amount(access.subscription_credits_remaining),purchased=amount(root.purchased_credits_remaining)??amount(access.purchased_credits_remaining),total=amount(access.total_usable_credits),rollover=amount(sub.rollover_credits);
 if(malformed||[monthly,remaining,purchased,total,rollover].every(v=>v===null))throw new Error('服务商返回了无法读取的数据');
 const windows=[];if(monthly>0&&remaining!==null){const used=Math.max(0,monthly-Math.max(0,remaining)),t=Date.parse(sub.current_period_end);windows.push({name:'月度额度',seconds:2592000,reportsLength:false,usedPercent:Math.min(100,100*used/monthly),reset:Number.isFinite(t)?new Date(t).toISOString():null,exhausted:remaining<=0});}
 const balance=total??purchased,balances=balance===null?[]:[{currency:'USD',amount:balance}];if(!windows.length&&!balances.length)throw new Error('服务商未报告可显示的额度或余额');return {windows,balances,plan:typeof sub.plan==='string'?sub.plan.trim()||null:null};
}
async function fetchNous(transport,home,now){const auth=await storedLogin(home,now);try{return parseAccount(await transport(auth.portal+'/api/oauth/account',{Authorization:`Bearer ${auth.token}`,Accept:'application/json'}));}catch(e){if(e.status===401||e.status===403)throw new Error('Hermes 登录已过期，请先运行 Hermes 更新登录');throw e;}}
module.exports={trustedPortal,jwtExpiry,login,storedLogin,parseAccount,fetchNous};
