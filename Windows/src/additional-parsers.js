// Additional provider adapters, based on Pulse's service-specific rules.
const {number}=require('./parsers');
const bounded=n=>Math.max(0,Math.min(100,n));
const validEpoch=n=>{if(n===null||n<=0||!Number.isFinite(new Date(n*1000).getTime()))return null; return new Date(n*1000).toISOString()};
function elevenlabs(root){
 const used=number(root.character_count),limit=number(root.character_limit),reset=number(root.next_character_count_reset_unix);
 const windows=used!==null&&used>=0&&limit!==null&&limit>0?[{id:'elevenlabs.characters',name:'字符额度',seconds:2592000,reportsLength:false,usedPercent:bounded(100*used/limit),reset:validEpoch(reset),exhausted:used>=limit}]:[];
 const plan=typeof root.tier==='string'?root.tier.trim().replaceAll('_',' ').replace(/\b\w/g,s=>s.toUpperCase())||null:null;
 return {windows,plan};
}
function synthetic(root){
 const slots=(root.rollingFiveHourLimit || root.weeklyTokenLimit || root.search?.hourly)?root:(root.data??root);
 const windows=[];
 const fraction=(used,remaining,limit)=>{used=number(used);remaining=number(remaining);limit=number(limit);if(limit===null||limit<=0)return null;if(used!==null&&used>=0)return bounded(100*used/limit);if(remaining!==null&&remaining>=0)return bounded(100*Math.max(limit-remaining,0)/limit);return null};
 const add=(w,id,name,seconds,scope,percent,reset)=>{if(w&&percent!==null)windows.push({id,name,scope,seconds,reportsLength:true,usedPercent:percent,reset:typeof reset==='string'&&Number.isFinite(Date.parse(reset))?new Date(reset).toISOString():null,exhausted:w.limited===true||percent>=100});};
 let w=slots.rollingFiveHourLimit; if(w)add(w,'synthetic.five_hour','5 小时额度',18000,null,fraction(null,w.remaining,w.max),null);
 w=slots.weeklyTokenLimit; if(w){const left=number(w.percentRemaining); const dollars=x=>typeof x==='string'?number(x.trim().replace(/[$,]/g,'')):null;const pct=left!==null&&left>=0&&left<=100?100-left:fraction(null,dollars(w.remainingCredits),dollars(w.maxCredits));add(w,'synthetic.weekly','每周额度',604800,null,pct,null);}
 w=slots.search?.hourly; if(w)add(w,'synthetic.search_hourly','每小时额度',3600,'Search',fraction(w.requests,w.remaining,w.limit),w.renewsAt);
 windows.sort((a,b)=>a.seconds-b.seconds);return {windows,plan:typeof slots.plan==='string'?slots.plan.trim()||null:null};
}
function zai(root,provider='zai'){
 if(root.success!==true || root.code!==200){const m=String(root.msg??'').toLowerCase();const c=number(root.code);if(m.includes('coding plan'))throw new Error('账号没有可用的 Coding Plan');if(/token|auth|key|unauthor|forbidden|credential|身份验证|鉴权|认证|令牌|未授权|无权限|密钥/.test(m)||[401,403].includes(c)||(c>=1000&&c<=1099))throw new Error('服务商拒绝了密钥');if(c===429)throw new Error('服务商请求过于频繁');throw new Error('服务商返回错误');}
 const windows=[];
 for(const [index,x] of (Array.isArray(root.data?.limits)?root.data.limits:[]).entries()){if(!['TOKENS_LIMIT','CREDIT_LIMIT','TIME_LIMIT'].includes(x.type))continue;const unit=number(x.unit),count=number(x.number);if(!Number.isInteger(unit)||!Number.isInteger(count)||count<=0)continue;const minutes=x.type==='TIME_LIMIT'&&unit===5&&count===1?43200:({1:1440,3:60,5:1,6:10080}[unit]??0)*count;if(!minutes || !Number.isSafeInteger(minutes)||minutes>10*366*1440)continue;const usage=number(x.usage),remaining=number(x.remaining),current=number(x.currentValue);let pct=null;if(usage!==null&&usage>0){let used=null;if(remaining!==null)used=Math.max(usage-remaining,current??usage-remaining);else if(current!==null)used=current;if(used!==null)pct=bounded(Math.min(used,usage)/usage*100);}if(pct===null){const reported=number(x.percentage);if(reported!==null)pct=bounded(reported);}if(pct===null)continue;const at=number(x.nextResetTime);windows.push({id:provider+'.'+x.type+'.'+unit+'-'+count+'.'+index,name:minutes===300?'5 小时额度':minutes===10080?'每周额度':minutes===43200?'月度额度':`${minutes} 分钟额度`,scope:x.type==='TIME_LIMIT'?'MCP':null,seconds:minutes*60,reportsLength:true,usedPercent:pct,reset:validEpoch(at===null?null:at/1000),exhausted:pct>=100});}
 windows.sort((a,b)=>a.seconds-b.seconds);const d=root.data??{};const plan=[d.planName,d.plan,d.plan_type,d.packageName,d.level].find(v=>typeof v==='string'&&v.trim())?.trim()??null;return {windows,plan};
}
module.exports={elevenlabs,synthetic,zai};
function claude(root){
 const windows=[]; const spent=x=>x.locked_reason!=null || (typeof x.severity==='string' && !['normal','ok','none','healthy','warning','warn'].includes(x.severity.toLowerCase()));
 for(const x of root.limits??[]){const seconds=x.kind==='session'?18000:['weekly_all','weekly_scoped'].includes(x.kind)?604800:null;const used=number(x.percent);if(seconds===null||used===null)continue;windows.push({name:seconds===18000?'5 小时额度':'每周额度',scope:x.scope?.model?.display_name??null,seconds,usedPercent:bounded(used),reset:x.resets_at??null,exhausted:spent(x)});}
 if(!windows.length) for(const [key,name,seconds] of [['five_hour','5 小时额度',18000],['seven_day','每周额度',604800]]){const item=root[key],used=number(item?.utilization);if(used!==null)windows.push({name,scope:null,seconds,usedPercent:bounded(used),reset:item.resets_at??null,exhausted:spent(item)});}
 const rows=(Array.isArray(root.seven_day_breakdown?.rows)?root.seven_day_breakdown.rows:[]).flatMap((x,index)=>{const name=typeof x?.display_name==='string'?x.display_name.trim():'';return name&&typeof x.percent==='number'&&Number.isFinite(x.percent)&&x.percent>0&&x.percent<=100?[{name,percent:x.percent,index}]:[]}).sort((a,b)=>b.percent-a.percent||a.index-b.index).slice(0,4).map(({name,percent})=>({name,percent}));const asOf=root.seven_day_breakdown?.as_of;const productShare=rows.length?{rows,...(typeof asOf==='string'&&Number.isFinite(Date.parse(asOf))?{asOf}: {})}:null;return {windows,...(productShare?{productShare}:{})};
}
module.exports.claude=claude;
function opencode(root){const windows=[];for(const [key,name,seconds,reportsLength] of [['rolling','5 小时额度',18000,true],['weekly','每周额度',604800,true],['monthly','月度额度',2592000,false]]){const w=root.usage?.[key],used=number(w?.percent);if(used!==null)windows.push({name,seconds,reportsLength,usedPercent:bounded(used),reset:w.resetsAt??null,exhausted:String(w.status??'ok').toLowerCase()!=='ok'});}return {windows};}
module.exports.opencode=opencode;
function minimax(root){
 const status=number(root.base_resp?.status_code)??0;if(status!==0){const m=String(root.base_resp?.status_msg??'').toLowerCase();throw new Error(status===1004||/token|auth|login|cookie|credential/.test(m)?'服务商拒绝了密钥':'服务商返回错误');}
 const payload=root.data&&typeof root.data==='object'?root.data:root,windows=[];
 for(const model of payload.model_remains??[]){const scope=typeof model.model_name==='string'&&model.model_name.trim().toLowerCase()!=='general'?model.model_name.trim()||null:null;
  for(const [kind,prefix] of [['interval','current_interval'],['weekly','current_weekly']]){const total=number(model[`${prefix}_total_count`]),left=number(model[`${prefix}_usage_count`]),remaining=number(model[`${prefix}_remaining_percent`]),status=number(model[`${prefix}_status`]);if(status===3&&(total??0)===0&&(remaining??0)>=100)continue;let used=remaining!==null?bounded(100-remaining):total!==null&&total>0&&left!==null?bounded(100*(total-left)/total):null;if(used===null)continue;
   let seconds,reset;if(kind==='interval'){const start=number(model.start_time),end=number(model.end_time);if(start===null||end===null||end<=start)continue;seconds=Math.floor((end-start)/1000);if(!Number.isSafeInteger(seconds)||seconds<=0)continue;reset=validEpoch(end/1000);}else {seconds=604800;const end=number(model.weekly_end_time);reset=validEpoch(end===null?null:end/1000);}
   windows.push({name:seconds===18000?'5 小时额度':seconds===604800?'每周额度':seconds===2592000?'月度额度':`${seconds/3600} 小时额度`,scope,seconds,usedPercent:used,reset});
  }
 }
 windows.sort((a,b)=>a.seconds-b.seconds);const plan=['current_subscribe_title','plan_name','combo_title','current_plan_title'].map(k=>payload[k]).find(v=>typeof v==='string'&&v.trim())?.trim()??null;
 return {windows,plan};
}
module.exports.minimax=minimax;
function cline(root){if(root.success!==true||!Array.isArray(root.data?.limits))throw new Error('服务商返回了无法读取的数据');const known={five_hour:['5 小时额度',18000,true],weekly:['每周额度',604800,true],monthly:['月度额度',2592000,false]},windows=[];for(const item of root.data.limits){const spec=known[item.type],pct=number(item.percentUsed);if(!spec||pct===null||pct<0)continue;windows.push({id:'clinepass.'+item.type,name:spec[0],seconds:spec[1],reportsLength:spec[2],usedPercent:bounded(pct),reset:typeof item.resetsAt==='string'&&Number.isFinite(Date.parse(item.resetsAt))?new Date(item.resetsAt).toISOString():null,exhausted:pct>=100});}windows.sort((a,b)=>a.seconds-b.seconds);return {windows};}
function kilo(root){
 if(!root||typeof root!=='object')throw new Error('服务商返回了无法读取的数据');const entries=[root[0]??null,root[1]??null];if(!entries.some(x=>x?.result||x?.error))throw new Error('服务商返回了无法读取的数据');
 for(const entry of entries){if(entry?.error){const text=JSON.stringify(entry.error).toLowerCase();throw new Error(/unauthorized|forbidden/.test(text)?'服务商拒绝了密钥':'服务商返回了无法读取的数据');}}
 const payload=x=>{const d=x?.result?.data;return d&&Object.hasOwn(d,'json')?d.json:d};const blocks=payload(entries[0]),sub=payload(entries[1])?.subscription;
 let micro=number(blocks?.totalBalance_mUsd);if(micro===null){const amounts=(blocks?.creditBlocks??[]).map(x=>number(x.balance_mUsd)).filter(x=>x!==null);micro=amounts.length?amounts.reduce((a,b)=>a+b,0):null;}
 const balances=micro!==null&&micro>=0?[{currency:'USD',amount:micro/1e6}]:[];const windows=[];if(sub){const used=number(sub.currentPeriodUsageUsd),base=number(sub.currentPeriodBaseCreditsUsd),bonus=number(sub.currentPeriodBonusCreditsUsd);const size=base+(bonus>0?bonus:0);if(used!==null&&used>=0&&base!==null&&base>=0&&size>0)windows.push({name:'订阅额度',seconds:2592000,reportsLength:false,usedPercent:bounded(100*used/size),reset:sub.nextBillingAt??null,exhausted:used>=size});}
 const tiers={tier_19:'Starter',tier_49:'Pro',tier_199:'Expert'};return {windows,balances,plan:sub?(tiers[sub.tier]??'Kilo Pass'):null};
}
module.exports.cline=cline;module.exports.kilo=kilo;
