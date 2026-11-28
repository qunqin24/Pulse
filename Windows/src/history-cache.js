// Share a short-lived account history read without mixing credentials or currencies.
class HistoryCache {
 constructor(ttl=60000,now=Date.now){this.ttl=ttl;this.now=now;this.last=null;this.running=null;this.generation=0}
 forget(){this.generation++;this.last=null;this.running=null}
 async get(identity,load){const at=this.now();if(this.last?.identity===identity&&at-this.last.at<this.ttl){if(this.last.error)throw this.last.error;return this.last.value}if(this.running?.identity===identity)return this.running.promise;const generation=this.generation;const promise=Promise.resolve().then(load).then(value=>{if(generation===this.generation)this.last={identity,at:this.now(),value};return value},error=>{if(generation===this.generation)this.last={identity,at:this.now(),error};throw error}).finally(()=>{if(this.running?.promise===promise)this.running=null});this.running={identity,promise};return promise}
}
module.exports=HistoryCache;
