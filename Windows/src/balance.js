// A balance-only account has no provider-reported allowance. Any ring is an estimate.
function applyBalance(reading,id,settings={},marks={},now=Date.now()){
 if(reading?.status==='error'||!Array.isArray(reading?.balances)||!reading.balances.length||reading.windows?.length)return {reading,changed:false};
 const balances=reading.balances.filter(x=>typeof x?.currency==='string'&&Number.isFinite(x.amount));if(!balances.length)return {reading,changed:false};let changed=false;
 for(const item of balances){const key=JSON.stringify([id,item.currency]),old=marks[key];if(!old||!Number.isFinite(old.peak)||item.amount>old.peak){marks[key]={peak:Math.max(item.amount,0),at:new Date(now).toISOString()};changed=true;}}
 const selected=balances.find(x=>x.currency===settings.currency)??balances.find(x=>x.amount>0)??balances[0];const basis=settings.basis??'sinceTopUp';const peak=marks[JSON.stringify([id,selected.currency])]?.peak;const budget=Number.isFinite(settings.budget)&&settings.budget>0?settings.budget:null;const denom=basis==='sinceTopUp'?peak:basis==='budget'?budget:null;
 let window=null;if(Number.isFinite(denom)&&denom>0){const percent=Math.max(0,Math.min(100,100*(denom-selected.amount)/denom));window={id:'balance',name:'余额',kind:'balance',seconds:2592000,reportsLength:false,usedPercent:percent,reset:null,estimatedFrom:basis,exhausted:id==='deepseek'&&reading.available===false};}
 return {reading:{...reading,selectedBalance:selected,windows:window?[window]:[]},changed};
}
module.exports={applyBalance};
