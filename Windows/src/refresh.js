const diagnostics=require('./connection-diagnostics');
// Isolates refreshes by account: a slow service cannot hold the others back.
class RefreshCoordinator {
 constructor({fetch,isEnabled,onChange,onRefreshing=()=>{},onRaw=()=>{},reconcile=(id,result)=>result}){this.reconcile=reconcile;this.onRaw=onRaw;this.fetch=fetch;this.isEnabled=isEnabled;this.onChange=onChange;this.onRefreshing=onRefreshing;this.readings={};this.diagnostics={};this.generations=new Map();this.refreshing=new Map();}
 invalidate(id){this.generations.set(id,(this.generations.get(id)||0)+1);delete this.readings[id];delete this.diagnostics[id];if(this.refreshing.delete(id))this.onRefreshing(id,false);}
 publish(id,reading){if(!this.isEnabled(id))return false;const previous=this.readings[id];this.readings[id]={...reading,status:'live'};this.onChange(this.readings,id,previous);return true;}
 async refreshOne(id){
  if(!this.isEnabled(id))return;
  const generation=(this.generations.get(id)||0)+1;this.generations.set(id,generation);const wasRefreshing=this.refreshing.has(id);this.refreshing.set(id,generation);if(!wasRefreshing)this.onRefreshing(id,true);
  const replies=[];let result;try{result={...await require('./response-log').capture(replies,()=>this.fetch(id)),status:'live'};}catch(e){const old=this.readings[id];result={status:'error',error:e.message,previous:old?.status==='live'?old:old?.previous};}
  if(this.refreshing.get(id)===generation){this.refreshing.delete(id);this.onRefreshing(id,false);}
  if(this.generations.get(id)!==generation||!this.isEnabled(id))return;
  const previous=this.readings[id];if(result.status==='live')try{this.onRaw(id,result)}catch{}result=this.reconcile(id,result,previous);this.readings[id]=result;this.diagnostics[id]={...diagnostics.completed(this.diagnostics[id],result),responses:replies.slice(),routes:(replies.routes??[]).slice()};this.onChange(this.readings,id,previous);
 }
 async refreshAll(ids){await Promise.all(ids.map(id=>this.refreshOne(id)));}
}
module.exports={RefreshCoordinator};
