// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
(function(root){
 function values(window,remaining){
  if(!window||!Number.isFinite(window.usedPercent))return null;
  const used=Math.min(100,Math.max(0,window.usedPercent));
  return {used,figure:remaining?100-used:used,arc:(window.exhausted||used>=100)?100:(remaining?100-used:used)};
 }
 function windowKey(w){if(!w||typeof w!=='object')return null;if(typeof w.id==='string'&&w.id.trim())return 'id:'+w.id.trim();if(typeof w.name!=='string'||!w.name.trim())return null;return 'window:'+JSON.stringify([w.name.trim(),typeof w.scope==='string'?w.scope:null,Number.isFinite(w.seconds)?w.seconds:null]);}
 function select(windows,pinned){
  const valid=(windows??[]).filter(w=>w&&Number.isFinite(w.usedPercent));if(!valid.length)return {headline:null,second:null};
  const fullest=items=>items.reduce((a,b)=>!a||b.usedPercent>a.usedPercent?b:a,null),headline=valid.find(w=>pinned&&(windowKey(w)===pinned||windowKey({...w,id:undefined})===pinned||Array.isArray(w.legacyKeys)&&w.legacyKeys.includes(pinned)))??fullest(valid),rest=valid.filter(w=>w!==headline),group=rest.filter(w=>(w.scope??null)===(headline.scope??null));return {headline,second:fullest(group.length?group:rest)};
 }
 function amount(window,remaining){const a=window?.amounts,value=remaining?a?.remaining:a?.used;if(!a||!Number.isFinite(a.limit)||a.limit<=0||!Number.isFinite(value)||value<0)return null;const format=n=>{if(typeof a.currency==='string'&&/^[A-Z]{3}$/.test(a.currency)){try{return new Intl.NumberFormat(undefined,{style:'currency',currency:a.currency,maximumFractionDigits:2}).format(n)}catch{}}return new Intl.NumberFormat(undefined,{maximumFractionDigits:1,notation:n>=1000000?'compact':'standard'}).format(n)};return `${format(value)} / ${format(a.limit)}`;}
 function clock(window,mode,now=Date.now()){if(!window?.reportsLength||!Number.isFinite(window.seconds)||window.seconds<=0||!['elapsed','remaining'].includes(mode))return null;const reset=Date.parse(window.reset);if(!Number.isFinite(reset))return null;const elapsed=Math.max(0,Math.min(1,1-(reset-now)/(window.seconds*1000)));return mode==='remaining'?1-elapsed:elapsed;}
 function updated(value,now=Date.now()){const stamp=Date.parse(value);if(!Number.isFinite(stamp))return null;const age=Math.max(0,now-stamp);if(age<60000)return '刚刚更新';const units=age<3600000?[Math.floor(age/60000),'分钟']:age<86400000?[Math.floor(age/3600000),'小时']:[Math.floor(age/86400000),'天'];return units[0]+units[1]+'前更新';}
 function percent(value){if(!Number.isFinite(value)||value<=0)return 0;if(value>=100)return 100;return Math.max(1,Math.min(99,Math.round(value)));}
 function tone(window,threshold=75){const used=Number.isFinite(window?.usedPercent)?window.usedPercent:0;if(window?.exhausted||used>=100)return 'spent';if(used>=([60,70,75,80,85,90].includes(threshold)?threshold:75))return 'danger';if(used>=50)return 'warning';return 'normal'}
 function customTint(window,color){return tone(window)==='spent'||typeof color!=='string'||!/^#[0-9a-f]{6}$/i.test(color)?null:color.toUpperCase()}
 const api={values,select,amount,clock,percent,updated,tone,windowKey,customTint};if(typeof module!=='undefined')module.exports=api;else root.usageDisplay=api;
})(globalThis);
