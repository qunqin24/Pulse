// Prime Agent session paths, derived from Pulse under Apache-2.0.
const fs=require('node:fs'),path=require('node:path'),{value}=require('./pi-paths');
function settings(file,home){try{const raw=JSON.parse(fs.readFileSync(file,'utf8')).sessionDir;if(typeof raw!=='string')return [];const dir=raw===''?path.dirname(file):value(raw,home);return dir?[dir,path.join(path.dirname(dir),'session-artifacts')]:[]}catch{return []}}
function roots(home,env=process.env){const explicit=value(env.PRIME_AGENT_SESSION_DIR??env.PRIME_AGENT_CODING_AGENT_SESSION_DIR,home),base=value(env.PRIME_AGENT_CODING_AGENT_DIR,home)??path.join(home,'.prime','agent'),sessions=explicit??path.join(base,'sessions'),artifacts=path.join(path.dirname(sessions),'session-artifacts');return [...new Set([sessions,artifacts,...settings(path.join(path.dirname(sessions),'settings.json'),home)].map(p=>path.normalize(p)))]}
module.exports={settings,roots};
