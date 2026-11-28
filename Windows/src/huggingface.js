// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os');
async function savedToken(home=os.homedir()){
 let text;try{text=await fs.readFile(path.join(home,'.cache','huggingface','token'),'utf8');}catch(e){if(e.code==='ENOENT')return null;throw new Error('无法读取 Hugging Face 本地登录文件');}
 let token=(text.split(/[\r\n]+/).find(Boolean)??'').trim();if(token.length>=2&&((token[0]==='"'&&token.at(-1)==='"')||(token[0]==="'"&&token.at(-1)==="'")))token=token.slice(1,-1).trim();return token||null;
}
function parseQuota(root){
 if(!root||typeof root!=='object'||Array.isArray(root))throw new Error('服务商返回了无法读取的数据');
 const {base,current,resetsAt}=root;if(typeof base!=='number'||!Number.isFinite(base)||base<=0||typeof current!=='number'||!Number.isFinite(current)||current<0)throw new Error('服务商未报告可显示的额度');
 let reset=null;if(typeof resetsAt==='string'&&Number.isFinite(Date.parse(resetsAt)))reset=new Date(resetsAt).toISOString();else if(typeof resetsAt==='number'&&Number.isFinite(resetsAt)&&resetsAt>0&&resetsAt<64092211200)reset=new Date(resetsAt*1000).toISOString();
 return {windows:[{name:'每日额度',scope:'ZeroGPU',seconds:86400,reportsLength:false,usedPercent:Math.min(100,Math.max(0,100*(base-current)/base)),reset,exhausted:current<=0}]};
}
async function fetchQuota(key,transport,home){
 const pasted=typeof key==='string'&&key.trim()?key.trim():null,token=pasted??await savedToken(home);if(!token)throw new Error('请在设置中填写访问令牌，或先运行 hf auth login');
 try{return parseQuota(await transport('https://huggingface.co/api/spaces/zero-gpu/quota',{Authorization:`Bearer ${token}`,Accept:'application/json'}));}catch(e){if(!pasted&&(e.status===401||e.status===403))throw new Error('Hugging Face 本地登录已过期，请重新登录');throw e;}
}
module.exports={savedToken,parseQuota,fetchQuota};
