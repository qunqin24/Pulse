// Model group slots follow Pulse's all-or-nothing split rules (Apache-2.0).
(function(root){
function groups(reading){const data=reading?.status==='live'?reading:reading?.previous,windows=data?.windows;if(!Array.isArray(windows)||!windows.length||windows.some(w=>typeof w.scope!=='string'||!w.scope.trim()))return [];return [...new Set(windows.map(w=>w.scope))]}
function slots(id,reading,split,shown){if(id!=='antigravity'||!split)return [{id,group:null}];const all=groups(reading);if(all.length<2||all.length>3)return [{id,group:null}];const chosen=Array.isArray(shown)?all.filter(x=>shown.includes(x)):all;return chosen.length?chosen.map(group=>({id,group})):[{id,group:null}]}
function budget(id,split,shown){return id==='antigravity'&&split?(Array.isArray(shown)?Math.min(3,Math.max(1,shown.length)):3):1}
function choose(all,shown,group,on){if(!Array.isArray(all)||!all.includes(group)||typeof on!=='boolean')throw Error('无效的模型分组');let chosen=Array.isArray(shown)?[...shown]:[...all];if(on&&!chosen.includes(group))chosen.push(group);if(!on)chosen=chosen.filter(x=>x!==group);if(!chosen.some(x=>all.includes(x)))throw Error('请至少保留一个模型分组');return all.every(x=>chosen.includes(x))?null:chosen}
const api={groups,slots,budget,choose};if(typeof module!=='undefined')module.exports=api;else root.railSlots=api;
})(globalThis);
