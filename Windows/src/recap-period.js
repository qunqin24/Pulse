// Parse the same calendar keys as Pulse --recap. No filesystem access.
function period(text,now=new Date()){
 if(text==null){if(!Number.isFinite(+now))return null;return {key:String(now.getFullYear()).padStart(4,'0')+'-'+String(now.getMonth()+1).padStart(2,'0'),kind:'month',date:new Date(now.getFullYear(),now.getMonth(),1)}}
 if(typeof text!=='string')return null;const m=/^(week-)?(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$/.exec(text);if(!m||m[1]&&!m[4])return null;const y=+m[2],month=m[3]?+m[3]:1,day=m[4]?+m[4]:1;if(y<1||month<1||month>12||day<1||day>31)return null;const d=new Date(0);d.setHours(0,0,0,0);d.setFullYear(y,month-1,day);if(d.getFullYear()!==y||d.getMonth()!==month-1||d.getDate()!==day)return null;return {key:text,kind:m[1]?'week':m[4]?'day':m[3]?'month':'year',date:d};
}
module.exports={period};
