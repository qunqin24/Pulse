// Connection metadata is intentionally separate from credentials and responses.
function completed(previous,reading,now=Date.now()){
 const time=new Date(now).toISOString(), data=reading?.status==='live'?reading:reading?.previous;
 const successful=reading?.status==='live'?time:previous?.lastSuccessfulAt??null;
 return {status:reading?.status==='live'?'available':'unavailable',checkedAt:time,lastSuccessfulAt:successful,source:typeof data?.source==='string'?data.source:null,showingPrevious:reading?.status!=='live'&&!!data};
}
function report(provider,diagnostic){
 const id=typeof provider==='string'&&/^[a-z0-9_-]{1,80}$/i.test(provider)?provider:'unknown';
 const d=diagnostic??{};
 const date=v=>typeof v==='string'&&Number.isFinite(Date.parse(v))?new Date(v).toISOString():'not recorded';
 const source=typeof d.source==='string'&&/^[a-z0-9 _-]{1,80}$/i.test(d.source)?d.source:'not recorded';
 return ['Pulse connection diagnostics','Provider: '+id,'Status: '+(['available','unavailable'].includes(d.status)?d.status:'not checked'),'Checked at: '+date(d.checkedAt),'Last successful check: '+date(d.lastSuccessfulAt),'Source: '+source,'Showing previous reading: '+(d.showingPrevious?'yes':'no')].join('\n');
}
module.exports={completed,report};
