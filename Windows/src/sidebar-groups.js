// Sidebar grouping follows Pulse's billing categories; enabled accounts keep panel order.
const api=new Set(['deepseek','sub2api','newapi','deepinfra','llmproxy','hyper','clawrouter','litellm','aixy','bifrost','atlas','moonshot','openaiapi','poe','replicate','typesafe','venice','vercel','perplexity','xai']);
function groups(providers){return [{id:'enabled',title:'已启用',providers:providers.filter(p=>p.enabled)}, {id:'subscription',title:'订阅',providers:providers.filter(p=>!p.enabled&&p.type!=='extension'&&!api.has(p.baseId??p.id))}, {id:'api',title:'API 和按量计费',providers:providers.filter(p=>!p.enabled&&p.type!=='extension'&&api.has(p.baseId??p.id))}, {id:'extensions',title:'扩展',providers:providers.filter(p=>!p.enabled&&p.type==='extension')}].filter(g=>g.providers.length)}
function normalize(value){return String(value??'').normalize('NFD').replace(/\p{M}/gu,'').toLocaleLowerCase()}
function matches(text,query){return normalize(text).includes(normalize(String(query??'').trim()))}
const sidebarGroups={groups,matches};if(typeof module!=='undefined')module.exports=sidebarGroups;
