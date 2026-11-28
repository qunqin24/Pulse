// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
const rank={operational:0,maintenance:1,unrecognised:2,degraded:3,partialOutage:4,fullOutage:5};
function changes(memory,id,components){const prior=memory[id]??{},next={},worse=[],recovered=[];for(const item of components){if(typeof item?.id!=='string')continue;const before=prior[item.id],severity=rank[item.state];if(['degraded','partialOutage','fullOutage'].includes(item.state)){if(before===undefined||severity>rank[before])worse.push(item);next[item.id]=item.state}else if(item.state==='operational'){if(before!==undefined)recovered.push(item)}else if(before!==undefined)next[item.id]=before}if(Object.keys(next).length)memory[id]=next;else delete memory[id];return {worse,recovered}}
function keep(memory,ids){const watched=new Set(ids);for(const id of Object.keys(memory))if(!watched.has(id))delete memory[id]}
module.exports={changes,keep};
