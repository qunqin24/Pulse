// Independent of notification settings: observe live usage and activity changes.
const key=require('./usage-display').windowKey;
class RobotCues{
 constructor(){this.windows=new Map();this.resets={};this.finished={};this.running=[]}
 observe(id,reading,now=Date.now()){const stamp=Date.parse(reading?.observedAt);if(reading?.status!=='live'||reading.sourceStale||!Number.isFinite(stamp)||stamp>now+60000||now-stamp>86400000)return;const seen=this.windows.get(id)??new Map();for(const w of reading.windows??[]){const k=key(w),percent=w?.usedPercent,reset=Date.parse(w?.reset);if(!k||!Number.isFinite(percent)||Number.isFinite(reset)&&reset<=now)continue;const old=seen.get(k),prepaid=['balance','topUp'].includes(w.kind),credit=['credits','sharedCredits','planCredits','dedicatedCredits'].includes(w.kind),moved=old&&Number.isFinite(old.reset)&&Number.isFinite(reset)&&reset-old.reset>60000;if(old&&!prepaid&&(moved||!credit&&old.percent-percent>=40))this.resets[id]=now;seen.set(k,{percent,reset})}this.windows.set(id,seen)}
 activity(ids,reason,now=Date.now()){const next=Array.isArray(ids)?ids:[];if(reason==='scan')for(const id of this.running)if(!next.includes(id))this.finished[id]=now;this.running=[...next]}
 remove(id){this.windows.delete(id);delete this.resets[id]}
 public(now=Date.now()){return {resets:Object.fromEntries(Object.entries(this.resets).filter(([,t])=>now-t>=0&&now-t<=20000)),finished:Object.fromEntries(Object.entries(this.finished).filter(([,t])=>now-t>=0&&now-t<=6000))}}
}
module.exports={RobotCues};
