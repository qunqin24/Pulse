// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
const {number}=require('./parsers');
function parseCopilot(root){
 if(!root||typeof root!=='object'||Array.isArray(root))throw new Error('服务商返回了无法读取的数据');
 const snapshots=root.quota_snapshots??{},stamp=root.quota_reset_date_utc??root.quota_reset_date,ms=typeof stamp==='string'?Date.parse(stamp):NaN,reset=Number.isFinite(ms)?new Date(ms).toISOString():null,windows=[];
 for(const [key,scope] of [['premium_interactions','Premium requests'],['chat','Chat'],['completions','Completions']]){
  const s=snapshots[key];if(!s||typeof s!=='object'||Array.isArray(s))continue;const entitlement=number(s.entitlement)??0,credits=number(s.credits_used)??0,remaining=number(s.percent_remaining),unlimited=s.unlimited===true;
  if(s.has_quota===false&&entitlement<=0&&credits<=0)continue;
  if(typeof s.has_quota!=='boolean'&&!unlimited&&entitlement<=0&&(number(s.remaining)??0)<=0&&(remaining??0)>=100)continue;
  if(unlimited||remaining===null)continue;
  const w={id:'copilot.'+key,name:'月度额度',scope,seconds:2592000,reportsLength:false,usedPercent:Math.max(0,Math.min(100,100-remaining)),reset,exhausted:remaining<=0&&s.overage_permitted!==true};
  const limit=number(s.entitlement),left=number(s.quota_remaining??s.remaining);if(limit!==null&&limit>0&&left!==null&&left>=0&&left<=limit)w.amounts={used:limit-left,remaining:left,limit};windows.push(w);
 }
 const raw=typeof root.copilot_plan==='string'?root.copilot_plan.trim():'';const known={individual:'Individual',free:'Free',business:'Business',enterprise:'Enterprise'};return {windows,plan:known[raw.toLowerCase()]??(raw||null)};
}
async function fetchCopilot(token,transport){
 if(typeof token!=='string'||!token.trim())throw new Error('请先登录 GitHub Copilot');const data=parseCopilot(await transport('https://api.github.com/copilot_internal/user',{Authorization:`token ${token.trim()}`,Accept:'application/json','X-Github-Api-Version':'2025-04-01','Editor-Version':'vscode/1.96.2','Editor-Plugin-Version':'copilot-chat/0.26.7'}));if(!data.windows.length)throw new Error('服务商未报告可显示的额度');return data;
}
module.exports={parseCopilot,fetchCopilot};
