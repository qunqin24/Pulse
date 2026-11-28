// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
(function(root){
 function resolve(stored,known){const valid=new Set(known),seen=new Set(),result=[];for(const id of [...(Array.isArray(stored)?stored:[]),...known])if(valid.has(id)&&!seen.has(id)){seen.add(id);result.push(id)}return result;}
 function move(ids,id,offset){const result=[...ids],i=result.indexOf(id),j=i+offset;if(i<0||j<0||j>=result.length)return result;[result[i],result[j]]=[result[j],result[i]];return result;}
 function moveOnto(ids,id,target){const result=[...ids],i=result.indexOf(id),j=result.indexOf(target);if(i<0||j<0||i===j)return result;result.splice(i,1);result.splice(j,0,id);return result;}
 function shownOrder(ids,shown){const allowed=new Set(shown);return [...shown.filter(id=>ids.includes(id)),...ids.filter(id=>!allowed.has(id))];}
 const api={resolve,move,moveOnto,shownOrder};if(typeof module!=='undefined')module.exports=api;else root.providerOrder=api;
})(globalThis);
