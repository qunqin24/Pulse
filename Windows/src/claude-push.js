// React to Claude Code's local status-line capture without polling its service.
const fs=require('node:fs'),path=require('node:path'),{readCaptured}=require('./claude-code');
class ClaudePush {
 constructor(onReading,{watch=fs.watch,read=readCaptured,debounceMs=200,retryMs=30000}={}){this.onReading=onReading;this.watch=watch;this.read=read;this.debounceMs=debounceMs;this.retryMs=retryMs;this.generation=0;this.watcher=null;this.retry=null;this.pending=null;this.lastStamp=0}
 stop(){this.generation++;clearTimeout(this.pending);clearTimeout(this.retry);this.pending=this.retry=null;if(this.watcher)this.watcher.close();this.watcher=null;this.lastStamp=0}
 start(dir){this.stop();const generation=this.generation,active=()=>this.generation===generation;const queue=()=>{clearTimeout(this.pending);this.pending=setTimeout(async()=>{let value;try{value=await this.read(dir)}catch{return}if(!active()||!value||value.sourceStale)return;const stamp=Date.parse(value.observedAt);if(!Number.isFinite(stamp)||stamp<=this.lastStamp)return;this.lastStamp=stamp;this.onReading(value)},this.debounceMs)};const connect=()=>{if(!active())return;try{const watcher=this.watch(dir,(_event,name)=>{if(name&&path.basename(String(name)).toLowerCase()==='pulse-usage.json')queue()});this.watcher=watcher;watcher.on('error',()=>{if(!active()||this.watcher!==watcher)return;watcher.close();this.watcher=null;this.retry=setTimeout(connect,this.retryMs)})}catch{this.retry=setTimeout(connect,this.retryMs)}};connect()}
}
module.exports={ClaudePush};
