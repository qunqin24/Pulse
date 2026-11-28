// Profiled provider responses, ported from Pulse's service-specific readers.
const {number}=require('./parsers');const bounded=x=>Math.max(0,Math.min(100,x));
const field=(obj,keys)=>{if(!obj||typeof obj!=='object')return null;for(const key of keys){const name=Object.keys(obj).find(k=>k.toLowerCase().replace(/[^a-z0-9]/g,'')===key);if(name!==undefined&&obj[name]!=null)return obj[name];}return null;};
const date=v=>{if(typeof v==='string'&&v.trim()&&Number.isFinite(Date.parse(v)))return new Date(Date.parse(v)).toISOString();const n=number(v),ms=n===null?NaN:n>1e10?n:n*1000;return n>0&&Number.isFinite(new Date(ms).getTime())?new Date(ms).toISOString():null;};
function chutes(root){
 const body=field(root,['data','result'])??root,subscription=field(body,['subscription','currentsubscription'])??{};const windows=[];
 const figures=p=>{const percent=number(field(p,['percentused','usagepercent','usedpercent']));if(percent!==null&&percent>=0)return bounded(percent);const limit=number(field(p,['limit','cap','max','quota','monthlylimit','requestlimit','tokenlimit'])),used=number(field(p,['used','usage','consumed','requests','requestcount','tokens','tokenusage'])),left=number(field(p,['remaining','available','left']));if(limit===null||limit<=0)return null;if(used!==null&&used>=0)return bounded(100*used/limit);if(left!==null&&left>=0)return bounded(100*Math.max(limit-left,0)/limit);return null;};
 const named={rolling:null,rollingwindow:null,rolling4h:14400,fourhour:14400,fourhourusage:14400,window4h:14400};
 for(const key of Object.keys(body).sort()){const normalized=key.toLowerCase().replace(/[^a-z0-9]/g,'');if(!Object.hasOwn(named,normalized))continue;const p=body[key];if(!p||typeof p!=='object'||Array.isArray(p))continue;let seconds=null;for(const [keys,mul] of [[['windowminutes','periodminutes','durationminutes'],60],[['windowhours','periodhours','durationhours'],3600],[['windowseconds','periodseconds','durationseconds'],1]]){const n=number(field(p,keys));if(n!==null&&n>0){const candidate=Math.round(n*mul);if(candidate>=3600&&candidate<2147483647)seconds=candidate;break;}}seconds??=named[normalized];const used=figures(p);if(seconds&&used!==null){windows.push({name:seconds===18000?'5 小时额度':`${seconds/3600} 小时额度`,seconds,usedPercent:used,reset:date(field(p,['resetat','resetsat','nextresetat','renewsat','periodend','currentperiodend','windowend'])),exhausted:used>=100});break;}}
 const month=field(body,['monthly','monthlyusage','billingperiod']),used=figures(month);if(used!==null)windows.push({name:'月度额度',seconds:2592000,reportsLength:false,usedPercent:used,reset:date(field(month,['resetat','resetsat','nextresetat','renewsat','periodend','currentperiodend','windowend'])),exhausted:used>=100});windows.sort((a,b)=>a.seconds-b.seconds);const plan=field(subscription,['planname','plan','tier']);return {windows,plan:typeof plan==='string'?plan.trim()||null:null};
}
function warp(root,now=Date.now()){
 if(Array.isArray(root.errors)&&root.errors.length)throw new Error('服务商返回错误');const account=root.data?.user?.user,limit=account?.requestLimitInfo;if(!limit)throw new Error('服务商返回了无法读取的数据');const windows=[];const cap=number(limit.requestLimit),used=number(limit.requestsUsedSinceLastRefresh);if(limit.isUnlimited!==true&&cap!==null&&cap>0&&used!==null&&used>=0)windows.push({name:'订阅额度',kind:'credits',seconds:2592000,reportsLength:false,usedPercent:bounded(100*used/cap),reset:date(limit.nextRefreshTime),exhausted:used>=cap});
 const grants=[...(account.bonusGrants??[]),...(account.workspaces??[]).flatMap(x=>x.bonusGrantsInfo?.grants??[])].flatMap(g=>{const granted=number(g.requestCreditsGranted),left=number(g.requestCreditsRemaining);return granted!==null&&granted>0&&left!==null&&left>=0?[{granted,left,expires:date(g.expiration)}]:[];});const total=grants.reduce((a,g)=>a+g.granted,0),left=grants.reduce((a,g)=>a+g.left,0);if(total>0){const expiries=grants.filter(g=>g.left>0&&g.expires&&Date.parse(g.expires)>now).map(g=>g.expires).sort();windows.push({name:'额外额度',kind:'topUp',seconds:2592000,reportsLength:false,usedPercent:bounded(100*Math.max(total-left,0)/total),reset:null,expiry:expiries[0]??null,exhausted:left<=0});}return {windows};
}
function deepinfra(root){
 const ledger=root?.stripe_balance,recent=root?.recent;
 if(typeof ledger!=='number'||!Number.isFinite(ledger)||typeof recent!=='number'||!Number.isFinite(recent))throw new Error('服务商返回了无法读取的数据');
 const spend=Math.max(recent,0),amount=0-(ledger+spend),limit=root.limit,windows=[];
 if(typeof limit==='number'&&Number.isFinite(limit)&&limit>0)windows.push({name:'支出上限',kind:'spend',seconds:2592000,reportsLength:false,usedPercent:bounded(100*spend/limit),reset:null,exhausted:spend>=limit});
 return {windows,balances:[{currency:'USD',amount}]};
}
function vercel(root){
 if(typeof root?.balance!=='string'||!/^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$/.test(root.balance.trim()))throw new Error('服务商返回了无法读取的数据');
 const amount=Number(root.balance);if(!Number.isFinite(amount))throw new Error('服务商返回了无法读取的数据');
 return {windows:[],balances:[{currency:'USD',amount}]};
}
module.exports={chutes,warp,deepinfra,vercel};
