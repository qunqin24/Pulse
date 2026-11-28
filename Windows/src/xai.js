// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
function credential(text){
 if(typeof text!=='string'||/[\x00-\x1f\x7f]/.test(text))return null;const i=text.indexOf(':');if(i<0)return null;const team=text.slice(0,i).trim(),key=text.slice(i+1).trim();
 if(!team||!key||team==='.'||team==='..'||/[\/\\\x00-\x1f\x7f]/.test(team)||/[\x00-\x1f\x7f]/.test(key))return null;
 try{return {team,key,encoded:encodeURIComponent(team)};}catch{return null;}
}
function parseBalance(reply){
 const raw=reply?.total?.val;if(typeof raw!=='string'||!/^\s*-?\d+(?:\.\d+)?\s*$/.test(raw))throw new Error('服务商返回了无法读取的数据');
 const cents=Number(raw);if(!Number.isFinite(cents))throw new Error('服务商返回了无法读取的数据');return {windows:[],balances:[{currency:'USD',amount:cents===0?0:-cents/100}]};
}
async function fetchBalance(text,transport){
 const auth=credential(text);if(!auth)throw new Error('请填写 TeamID:ManagementKey');
 const url=`https://management-api.x.ai/v1/billing/teams/${auth.encoded}/prepaid/balance`;
 return parseBalance(await transport(url,{Authorization:`Bearer ${auth.key}`,Accept:'application/json'}));
}
module.exports={credential,parseBalance,fetchBalance};
