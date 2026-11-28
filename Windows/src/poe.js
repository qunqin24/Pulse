// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
function parse(root){if(!root||typeof root!=='object'||Array.isArray(root))throw new Error('服务商返回了无法读取的数据');const raw=root.current_point_balance,value=typeof raw==='number'?raw:typeof raw==='string'&&raw.trim()?Number(raw):NaN;if(!Number.isFinite(value))throw new Error('服务商返回了无法读取的数据');return {windows:[],displayBalance:{amount:value,unit:'points'}};}
async function fetchPoe(key,transport){if(typeof key!=='string'||!key.trim())throw new Error('请在设置中填写 API 密钥');return parse(await transport('https://api.poe.com/usage/current_balance',{Authorization:'Bearer '+key.trim(),Accept:'application/json'}));}
module.exports={parse,fetchPoe};
