// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
const {number}=require('./parsers');
const periods={daily:{seconds:86400,name:'每日额度',reportsLength:true},weekly:{seconds:604800,name:'每周额度',reportsLength:true},monthly:{seconds:2592000,name:'月度额度',reportsLength:false},lifetime:{seconds:31536000,name:'总支出上限',reportsLength:false}};
function parseAixy(root){
 if(root?.object!=='key.usage'||root.currency!=='USD'||typeof root.key?.id!=='string'||!Array.isArray(root.budgets))throw new Error('服务商返回了无法读取的数据');const chosen=new Map();
 for(const b of root.budgets){const period=periods[b?.interval],limit=number(b?.limit_usd),targets=b?.applies_to;if(typeof b?.id!=='string'||!period||!Array.isArray(targets)||!targets.length||!targets.every(t=>t?.api_key_id===root.key.id&&(t?.project_id??null)===(root.key.project_id??null))||limit===null||limit<=0)continue;
  const hard=b.enforcement==='hard';if(!hard&&b.enforcement!=='monitor')continue;let used=null;if(hard){const spent=number(b.availability?.spent_usd),reserved=number(b.availability?.reserved_usd);if(b.availability?.status==='available'&&spent!==null&&reserved!==null)used=spent+reserved;}else if(b.spend_status==='available')used=number(b.spend_usd);if(used===null||!Number.isFinite(used)||used<0)continue;
  const ratio=used/limit,at=typeof b.resets_at==='string'?Date.parse(b.resets_at):NaN,w={id:'aixy.'+b.id,name:period.name,seconds:period.seconds,reportsLength:period.reportsLength,usedPercent:Math.min(100,ratio*100),reset:b.interval!=='lifetime'&&Number.isFinite(at)?new Date(at).toISOString():null,exhausted:ratio>=1};const old=chosen.get(b.interval);if(!old||(hard&&!old.hard)||(hard===old.hard&&ratio>old.ratio))chosen.set(b.interval,{hard,ratio,w});
 }
 const windows=[...chosen.values()].map(x=>x.w).sort((a,b)=>a.seconds-b.seconds);if(!windows.length)throw new Error('服务商未报告可显示的额度');return {windows};
}
module.exports={parseAixy};
