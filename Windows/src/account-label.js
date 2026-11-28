// Account display names, derived from Pulse under Apache-2.0.
function valid(value){return typeof value==='string'&&value.length<=200&&!/[\r\n\u0000-\u001f]/.test(value)}
function label(provider,names,id){const given=names?.[id];return provider?.type!=='extension'&&valid(given)&&given.trim()?given:provider.name}
module.exports={valid,label};
