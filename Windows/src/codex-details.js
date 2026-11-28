// Codex account details shared by the HTTP and app-server routes.
function plan(value){if(typeof value!=='string')return null;return ({free:'Free',go:'Go',plus:'Plus',pro:'Pro',prolite:'Pro 5x',team:'Team',business:'Business',enterprise:'Enterprise',edu:'Edu'})[value.toLowerCase()]??value}
function balance(node){if(!node||node.unlimited===true)return null;const raw=node.balance;if(typeof raw!=='string'&&typeof raw!=='number')return null;if(typeof raw==='string'&&!raw.trim())return null;const n=Number(raw);return {amount:Number.isFinite(n)?new Intl.NumberFormat(undefined,{maximumFractionDigits:2}).format(n):String(raw),unit:'积分'}}
module.exports={plan,balance};
