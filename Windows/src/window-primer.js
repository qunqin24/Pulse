// Eligibility and scheduling for the optional window starter, derived from Pulse.
const grace=60000,idleFreshness=300000,refreshRetry=60000;
function hoursValid(hours){return Number.isInteger(hours?.start)&&Number.isInteger(hours?.end)&&hours.start>=0&&hours.start<24&&hours.end>=0&&hours.end<24}
function contains(hours,time){if(!hoursValid(hours))return false;const hour=new Date(time).getHours();return hours.start===hours.end||hours.start<hours.end?hours.start===hours.end||hour>=hours.start&&hour<hours.end:hour>=hours.start||hour<hours.end}
function nextAllowed(hours,time){if(!hoursValid(hours)||!Number.isFinite(time))return null;if(contains(hours,time))return time;const d=new Date(time);let start=new Date(d.getFullYear(),d.getMonth(),d.getDate(),hours.start).getTime();if(start<=time)start=new Date(d.getFullYear(),d.getMonth(),d.getDate()+1,hours.start).getTime();return start}
function eligible(provider,window){if(!window||window.scope||window.estimatedFrom||window.estimate)return false;return provider==='claude'?window.seconds===18000:provider==='codex'&&(window.seconds===18000||window.seconds===604800)}
function resetTime(window){if(window?.reset===null||window?.reset===undefined)return null;const value=Date.parse(window.reset);return Number.isFinite(value)?value:null}
function isDue(reset,current,now,hours){if(!Number.isFinite(reset)||now<reset+grace||!contains(hours,now))return false;const next=resetTime(current);return next===null||next<=reset+grace}
function needsFreshReading(dueByClock,receivedAt,now){return !dueByClock&&(!Number.isFinite(receivedAt)||now-receivedAt>idleFreshness)}
class WindowState{
 constructor(reset=null){this.reset=reset&&Number.isFinite(reset.date)&&Number.isFinite(reset.seenAt)?{...reset}:null;this.clockArmed=false;this.current=null;this.nilSince=null}
 record(window,receivedAt,now,last){this.current=window??null;if(!window){this.nilSince=null;return}const date=resetTime(window);if(date===null){this.nilSince??=now;return}this.nilSince=null;if(date<=now)return;this.clockArmed=true;if(this.reset?.date===date&&!(last&&this.reset.seenAt<=last.date&&receivedAt>last.date))return;this.reset={date,seenAt:receivedAt}}
 idleStart(last,now){if(!this.current)return null;const date=resetTime(this.current);if(date!==null&&date>now)return null;const since=date??this.nilSince;if(since===null)return null;const idle=since+grace;if(!last)return idle;if(!this.reset||this.reset.date<=last.date)return null;if(last.outcome==='sent'&&this.reset.seenAt<=last.date)return null;return Math.max(idle,this.reset.date+grace)}
 dueByClock(last,now,hours){return !!(this.clockArmed&&this.reset&&this.reset.date>(last?.date??-Infinity)&&isDue(this.reset.date,this.current,now,hours))}
 nextStart(last,now,hours){const allow=time=>nextAllowed(hours,Math.max(now,time)),idle=this.idleStart(last,now),idleAt=idle===null?null:allow(idle);if(!this.clockArmed||!this.reset||this.reset.date<=(last?.date??-Infinity))return idleAt;const clock=allow(this.reset.date+grace);if(clock===null||!isDue(this.reset.date,this.current,clock,hours))return idleAt;return Math.min(clock,idleAt??clock)}
}
module.exports={grace,idleFreshness,refreshRetry,hoursValid,contains,nextAllowed,eligible,resetTime,isDue,needsFreshReading,WindowState};
