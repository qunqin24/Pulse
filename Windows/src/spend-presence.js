// Sources recognised by Pulse that do not persist authoritative token counts.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os');
function roots(home=os.homedir(),env=process.env){const expand=x=>x==='~'?home:x?.startsWith('~/')||x?.startsWith('~\\')?path.join(home,x.slice(2)):x,free=env.FREEBUFF_DATA_DIR?.trim(),xdg=expand(env.XDG_DATA_HOME?.trim())||path.join(home,'.local','share'),global=expand(env.CRUSH_GLOBAL_DATA?.trim()),local=expand(env.LOCALAPPDATA?.trim());return {Freebuff:free?[expand(free)]:['manicode','manicode-dev','manicode-staging'].map(x=>path.join(home,'.config',x)),Crush:[global&&path.join(global,'projects.json'),path.join(xdg,'crush','projects.json'),local&&path.join(local,'crush','projects.json'),path.join(home,'AppData','Local','crush','projects.json')].filter(Boolean)}}
function present(home,env,exists=fs.existsSync){return Object.entries(roots(home,env)).filter(([,paths])=>paths.some(exists)).map(([name])=>name)}
function empty(name){return {source:name,days:{},priceDays:{},hours:{},records:0,filesRead:0,warnings:name==='Freebuff'?['Freebuff 未保存可核实的 Token 计数']:[]}}
module.exports={roots,present,empty};
