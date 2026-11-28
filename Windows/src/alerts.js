// Persistent usage alert rules, derived from Pulse (Apache-2.0).
function evaluate(memory,account,reading,settings,now=Date.now()){
 if(!settings.threshold||reading?.status!=='live'||!Array.isArray(reading.windows))return [];
 const observed=Date.parse(reading.observedAt);if(!Number.isFinite(observed)||now-observed>30*60*1000||observed>now+60000)return [];
 const accountMemory=memory[account]??(memory[account]={}),occurrences={},alerts=[];
 for(const w of reading.windows){
  if(!Number.isFinite(w.usedPercent))continue;const reset=Date.parse(w.reset);if(Number.isFinite(reset)&&reset<=now)continue;
  const base=JSON.stringify(w.id??[w.name??'',w.scope??'',w.seconds??0]);const index=occurrences[base]??0;occurrences[base]=index+1;const id=JSON.stringify([base,index]);const seen=accountMemory[id];
  let announced=seen?.announced??0;const moved=seen&&Number.isFinite(seen.reset)&&Number.isFinite(reset)&&reset-seen.reset>60000;
  const credit=account==='kilo'||account==='elevenlabs'||['credits','sharedCredits','planCredits','dedicatedCredits'].includes(w.kind);
  const prepaid=['balance','topUp'].includes(w.kind);const turnover=seen&&!prepaid&&(moved||(!credit&&seen.usedPercent-w.usedPercent>=40));
  if(turnover){if(settings.reset&&announced>0)alerts.push({kind:'reset',window:w});announced=0;}
  const step=w.exhausted===true||(!prepaid&&Math.floor(w.usedPercent)>=100)?100:Math.floor(w.usedPercent)>=settings.threshold?settings.threshold:0;
  if(step>announced){alerts.push({kind:step===100?'spent':'threshold',step,window:w});announced=step;}
  accountMemory[id]={announced,usedPercent:w.usedPercent,reset:Number.isFinite(reset)?reset:null};
 }
 return alerts;
}
module.exports={evaluate};
function evaluateBalance(memory,account,reading,config,now=Date.now()){
 if(!config||!Number.isFinite(config.amount)||config.amount<=0||typeof config.currency!=='string'||reading?.status!=='live')return [];
 const observed=Date.parse(reading.observedAt);if(!Number.isFinite(observed)||now-observed>30*60*1000||observed>now+60000)return [];
 const balance=reading.balances?.find(b=>b.currency===config.currency&&Number.isFinite(b.amount));if(!balance)return [];
 const record=memory[account]??(memory[account]={}),prior=record.__balance,identity=JSON.stringify([config.currency,config.amount]);
 if(balance.amount<config.amount){if(prior!==identity){record.__balance=identity;return [{kind:'lowBalance',balance}];}}
 else record.__balance=null;
 return [];
}
module.exports.evaluateBalance=evaluateBalance;
function failureStanding(message){
 const text=String(message??'');if(/未报告可显示|没有.*订阅|没有可用的 Coding Plan/.test(text))return 'answered';
 if(/无法连接服务商|请求超时|响应超时|登录已过期|拒绝了密钥|HTTP (401|403|429|5\d\d)\b/.test(text))return 'failure';
 return 'neutral';
}
function evaluateFailure(memory,account,reading,enabled,now=Date.now()){
 if(!enabled||!reading)return [];const record=memory[account]??(memory[account]={});let f=record.__failure??{count:0,reported:false};
 if(reading.status==='live'){record.__failure={count:0,reported:false};return [];}
 if(reading.status!=='error')return [];const standing=failureStanding(reading.error);
 if(standing==='answered'){record.__failure={count:0,reported:false};return [];}if(standing!=='failure')return [];
 const old=Date.parse(reading.previous?.observedAt);if(Number.isFinite(old)&&now-old<=30*60*1000)return [];
 f={count:f.count+1,reported:f.reported};const alerts=[];if(f.count>=3&&!f.reported){f.reported=true;alerts.push({kind:'failure'});}record.__failure=f;return alerts;
}
module.exports.failureStanding=failureStanding;module.exports.evaluateFailure=evaluateFailure;
