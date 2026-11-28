// Estimate currency formatting, derived from Pulse under Apache-2.0.
(function(root,factory){if(typeof module==='object'&&module.exports)module.exports=factory();else root.pulseMoney=factory()})(globalThis,()=>{
const symbols={USD:'$',CNY:'¥',HKD:'HK$',TWD:'NT$',JPY:'¥',KRW:'₩',RUB:'₽'};
function rateEntry(value){const s=String(value??'').trim();if(!s)return null;let n;if(/^\d+(?:[.,]\d+)?$/.test(s))n=Number(s.replace(',','.'));else if(/^\d{1,3}(?:,\d{3})+(?:\.\d+)?$/.test(s))n=Number(s.replaceAll(',',''));else return undefined;return Number.isFinite(n)&&n>0&&n<=1000000?n:undefined}
function convert(usd,currency='USD',manual={},rates={}){const code=Object.hasOwn(symbols,currency)?currency:'USD',candidate=manual?.[code]??rates?.[code],rate=code==='USD'?1:typeof candidate==='number'&&Number.isFinite(candidate)&&candidate>0?candidate:null;return rate?{amount:usd*rate,code}:{amount:usd,code:'USD'}}
function estimate(usd,currency='USD',manual={},rates={}){const {amount,code}=convert(usd,currency,manual,rates),whole=code==='JPY'||code==='KRW',unit=whole?1:.01,symbol=symbols[code];if(amount>0&&amount<unit)return '< '+symbol+(whole?'1':'0.01');const fraction=whole||amount>=1000?0:2;return symbol+amount.toLocaleString(undefined,{minimumFractionDigits:fraction,maximumFractionDigits:fraction})}
return {symbols,rateEntry,convert,estimate};
});
