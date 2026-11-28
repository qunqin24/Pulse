// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
function figure(value){
 if(value==null||typeof value==='string'&&!value.trim())return null;
 if(typeof value==='number'&&Number.isFinite(value))return value;
 if(typeof value==='string'&&/^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$/.test(value.trim())){const n=Number(value);if(Number.isFinite(n))return n;}
 throw new Error('服务商返回了无法读取的数据');
}
function parseVenice(root){
 if(!root||typeof root!=='object'||Array.isArray(root)||typeof root.canConsume!=='boolean'||!root.balances||typeof root.balances!=='object'||Array.isArray(root.balances)||(root.consumptionCurrency!=null&&typeof root.consumptionCurrency!=='string'))throw new Error('服务商返回了无法读取的数据');
 const usd=figure(root.balances.usd),diem=figure(root.balances.diem);
 if(root.consumptionCurrency?.toUpperCase()==='DIEM'&&diem!==null)return {windows:[],displayBalance:{amount:diem,unit:'DIEM'}};
 if(usd!==null)return {windows:[],balances:[{currency:'USD',amount:usd}]};
 if(diem!==null)return {windows:[],displayBalance:{amount:diem,unit:'DIEM'}};
 throw new Error('服务商未报告可显示的余额');
}
module.exports={parseVenice};
