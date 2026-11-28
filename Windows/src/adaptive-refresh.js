// Derived from Pulse, Copyright (c) 2026 qunqin24, Apache-2.0.
const unwatched=new Set('deepseek commandcode sub2api newapi v2ex deepinfra chutes bifrost abacus atlas aixy clawrouter amp gitkraken dimagent hyper elevenlabs devpass huggingface litellm kilo llmproxy manus mistral moonshot neuralwatt notionai nous openaiapi perplexity poe synthetic t3chat replicate sakana v0 typesafe venice vercel raycastai xai xkiro zenmux zoommate'.split(' '));
function interval(signals={},watched=true,now=Date.now()){if(signals.constrained||signals.visible===false)return 1800000;const cap=watched?1800000:300000,ages=[signals.lastAgentActivity,signals.lastChange,signals.lastLooked].filter(x=>Number.isFinite(x)&&x<=now).map(x=>now-x);if(!ages.length)return cap;const quiet=Math.min(...ages),wait=quiet<300000?120000:quiet<3600000?300000:quiet<14400000?900000:1800000;return Math.min(wait,cap)}
function cadence(id,seconds,signals,now){return seconds>0?seconds*1000:interval(signals,!unwatched.has(id),now)}
function due(ids,asked,seconds,signals,now){return ids.filter(id=>!asked.has(id)||now-asked.get(id)>=cadence(id,seconds,signals,now)-1000)}
function wait(ids,asked,seconds,signals,now){if(!ids.length)return null;return Math.max(15000,Math.min(...ids.map(id=>asked.has(id)?Math.max(0,cadence(id,seconds,signals,now)-(now-asked.get(id))):0)))}
module.exports={interval,cadence,due,wait,unwatched};
