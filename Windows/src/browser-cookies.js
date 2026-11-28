// Read a single provider's selected cookies, only after the user asks.
const fs=require('node:fs'),path=require('node:path'),{DatabaseSync}=require('node:sqlite');
const configs={
 'opencode:console':{host:'opencode.ai',names:['__Host-console_session','auth'],module:'opencode-console',method:'cookie'},
 ollamacloud:{host:'ollama.com',names:['wos-session','__Secure-session','__Secure-next-auth.session-token','next-auth.session-token'],chunks:true,module:'ollama-cloud',method:'cookies'},
 abacus:{host:'abacus.ai',names:['sessionid','session_id','session_token','auth_token','access_token'],module:'abacus',method:'cookieHeader'},
 zoommate:{host:'zoom.us',names:['_zm_ssid','cf_clearance'],module:'zoommate',method:'cookieHeader'},
 replicate:{host:'replicate.com',names:['sessionid','csrftoken'],module:'replicate',method:'cookieHeader'},
 t3chat:{host:'t3.chat',names:['wos-session','_vcrcs'],module:'t3chat',method:'cookie'},
 notionai:{host:'notion.com',names:['token_v2'],module:'notion-ai',method:'cookie'},
 augment:{host:'app.augmentcode.com',names:['_session','web_rpc_proxy_session'],module:'augment',method:'cookie'},
 sakana:{host:'console.sakana.ai',names:['__Secure-authjs.session-token'],module:'sakana',method:'cookie'},
 perplexity:{host:'www.perplexity.ai',names:['__Secure-next-auth.session-token'],module:'perplexity',method:'cookie'},
 longcat:{host:'longcat.chat',names:['passport_token','uid'],module:'longcat',method:'cookieHeader'},
 mistral:{host:'mistral.ai',names:['csrftoken'],prefixes:['ory_session_'],module:'mistral',method:'cookies'},
 qwencloud:{host:'qwencloud.com',names:['login_qwencloud_ticket','login_aliyunid_ticket','qwen_sso_ticket','login_current_pk','login_aliyunid_pk','login_aliyunid_csrf','csrf','cna','sec_token'],module:'qwen-cloud',method:'cookies'},
 raycastai:{host:'www.raycast.com',names:['__raycast_session','csrf_token'],module:'raycast-ai',method:'cookie'},
 zed:{host:'zed.dev',names:['zed.session'],module:'zed',method:'cookie'},
 manus:{host:'manus.im',names:['session_id'],module:'agent-providers',method:'session',token:true},
 xiaomi:{host:'platform.xiaomimimo.com',names:['api-platform_serviceToken','userId','api-platform_ph','api-platform_slh'],module:'xiaomi',method:'cookies'},
 opendesign:{host:'open-design.ai',names:['__Secure-better-auth.session_token'],prefixes:['__Secure-better-auth.'],module:'open-design',method:'cookie'},
 typesafe:{host:'console.typesafe.ai',names:[],all:true,module:'typesafe',method:'cookie'},
 'qoder:international':{host:'qoder.com',names:[],all:true,module:'qoder',method:'cookie'},
 'qoder:china':{host:'qoder.com.cn',names:[],all:true,module:'qoder',method:'cookie'},
 'stepfun:international':{host:'platform.stepfun.ai',names:['Oasis-Token','Oasis-Webid','INGRESSCOOKIE'],module:'stepfun',method:'cookies'},
 'stepfun:china':{host:'platform.stepfun.com',names:['Oasis-Token','Oasis-Webid','INGRESSCOOKIE'],module:'stepfun',method:'cookies'}
};
function profilePaths(roaming){const root=path.join(roaming,'Mozilla','Firefox'),profiles=path.join(root,'Profiles'),found=[];try{const ini=fs.readFileSync(path.join(root,'profiles.ini'),'utf8');for(const section of ini.split(/^\s*\[/m).slice(1)){const lines=section.split(/\r?\n/),name=lines.shift()?.replace(/\].*$/,'');if(!/^Profile\d+$/.test(name??''))continue;const fields={};for(const line of lines){const i=line.indexOf('=');if(i>0)fields[line.slice(0,i).trim()]=line.slice(i+1).trim()}if(!fields.Path)continue;const dir=fields.IsRelative==='1'?path.resolve(root,fields.Path):path.resolve(fields.Path);if(fields.IsRelative==='1'&&!dir.toLowerCase().startsWith((path.resolve(root)+path.sep).toLowerCase()))continue;found.push({dir,preferred:fields.Default==='1'})}}catch{}try{for(const item of fs.readdirSync(profiles,{withFileTypes:true})){if(item.isDirectory())found.push({dir:path.join(profiles,item.name),preferred:false})}}catch{}const seen=new Set();return found.sort((a,b)=>Number(b.preferred)-Number(a.preferred)).filter(x=>{const k=x.dir.toLowerCase();if(seen.has(k))return false;seen.add(k);return true}).slice(0,100).map(x=>path.join(x.dir,'cookies.sqlite'))}
function readStore(file,config,now=Date.now()){let db;try{db=new DatabaseSync(file,{readOnly:true});const prefixes=[...(config.prefixes??[]),...(config.chunks?config.names.map(x=>x+'.'):[])],escape=s=>s.replace(/[\\%_]/g,'\\$&'),conditions=[...config.names.map(()=> 'name = ?'),...prefixes.map(()=>"name LIKE ? ESCAPE '\\'")],query=`SELECT host,name,value,expiry FROM moz_cookies WHERE (host=? OR host=? OR host LIKE ?) AND (${config.all?'1=1':conditions.join(' OR ')}) AND (expiry=0 OR expiry>?) ORDER BY length(host) DESC,expiry DESC LIMIT 200`,rows=db.prepare(query).all(config.host,'.'+config.host,'%.'+config.host,...config.names,...prefixes.map(x=>escape(x)+'%'),Math.floor(now/1000));const pairs=[];for(const r of rows){if(typeof r.name!=='string'||typeof r.value!=='string'||!r.value||/[\x00-\x20\x7f;,"\\]/.test(r.name+r.value))continue;pairs.push(r.name+'='+r.value)}const normalized=require('./'+config.module)[config.method](pairs.join('; '));if(config.token)return normalized?'session_id='+normalized:null;return typeof normalized==='string'?normalized:normalized?.header??null}catch{return null}finally{db?.close()}}
function readFirefox(id,roaming=process.env.APPDATA,now=Date.now()){const config=Object.hasOwn(configs,id)?configs[id]:null;if(!config||!roaming)throw Error('此服务商不支持从 Firefox 导入');for(const file of profilePaths(roaming)){if(!fs.existsSync(file))continue;const header=readStore(file,config,now);if(header)return header}throw Error('Firefox 中没有找到此服务商的有效登录，请先在 Firefox 登录。')}
module.exports={configs,profilePaths,readStore,readFirefox};
