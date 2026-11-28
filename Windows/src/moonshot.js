// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
const {createHash}=require('node:crypto');
const accepted=new Map();
const regions={international:{url:'https://api.moonshot.ai/v1/users/me/balance',currency:'USD'},china:{url:'https://api.moonshot.cn/v1/users/me/balance',currency:'CNY'}};

function parseMoonshot(reply,currency){
 if(!reply||typeof reply.code!=='number'||typeof reply.status!=='boolean')throw new Error('服务商返回了无法读取的数据');
 if(reply.code!==0||!reply.status)throw new Error('服务商返回错误');
 const amount=reply.data?.available_balance;
 if(typeof amount!=='number'||!Number.isFinite(amount))throw new Error('服务商返回了无法读取的数据');
 return {windows:[],balances:[{currency,amount}]};
}

async function fetchMoonshot(key,transport){
 if(!key||!key.trim())throw new Error('请在设置中填写 API 密钥');
 key=key.trim();const fingerprint=createHash('sha256').update(key).digest('hex');const known=accepted.get(fingerprint);
 const order=known?[known,...Object.keys(regions).filter(r=>r!==known)]:Object.keys(regions);
 for(const region of order){
  let reply;try{reply=await transport(regions[region].url,{Authorization:`Bearer ${key}`,Accept:'application/json'});}catch(error){if(error.status===401||error.status===403)continue;throw error;}
  const result=parseMoonshot(reply,regions[region].currency);accepted.set(fingerprint,region);return result;
 }
 throw new Error('Moonshot 密钥被拒绝，请检查密钥');
}
module.exports={parseMoonshot,fetchMoonshot};
