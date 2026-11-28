// Copyright (c) 2026 qunqin24. Derived from Pulse under Apache-2.0.
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const parsers = {...require('./parsers'),...require('./additional-parsers'),...require('./profile-parsers'),...require('./energy-providers')};
const providers = {
 antigravity: {name:'Antigravity', icon:'antigravity.svg', type:'local'},
 cursor: {name:'Cursor', icon:'cursor.svg', type:'local'},
 claude: {name:'Claude Code', icon:'claude.svg', type:'local'},
 volcengine: {name:'火山引擎', icon:'volcengine.svg', type:'key'},
 kiro: {name:'Kiro', icon:'kiro.svg', type:'local'},
 codex: {name:'Codex', icon:'openai.svg', type:'local'},
 factory: {name:'Factory', icon:'extension.svg', type:'key'},
 chutes: {name:'Chutes', icon:'chutes.svg', type:'key'},
 warp: {name:'Warp', icon:'extension.svg', type:'key'},
 kilo: {name:'Kilo Code', icon:'kilocode.svg', type:'key'},
 cline: {name:'ClinePass', icon:'cline.svg', type:'key'},
 minimax: {name:'MiniMax', icon:'minimax.svg', type:'key', sites:['international','china']},
 moonshot: {name:'Moonshot', icon:'moonshot.svg', type:'key'},
 deepinfra: {name:'DeepInfra', icon:'deepinfra.svg', type:'key'},
 vercel: {name:'Vercel AI Gateway', icon:'vercel.svg', type:'key'},
 huggingface: {name:'Hugging Face', icon:'huggingface.svg', type:'key'},
 xai: {name:'xAI API', icon:'xai.svg', type:'key'},
 venice: {name:'Venice', icon:'venice.svg', type:'key'},
 nous: {name:'Nous Portal', icon:'hermesagent.svg', type:'local'},
 copilot: {name:'GitHub Copilot', icon:'github.svg', type:'oauth'},
 atlas: {name:'Atlas Cloud', icon:'atlascloud.svg', type:'key'},
 neuralwatt: {name:'Neuralwatt', icon:'extension.svg', type:'key'},
 aixy: {name:'Aixy', icon:'extension.svg', type:'key'},
 devpass: {name:'DevPass', icon:'extension.svg', type:'key'},
 zenmux: {name:'ZenMux', icon:'zenmux.svg', type:'key'},
 abacus: {name:'Abacus AI', icon:'extension.svg', type:'key'},
 commandcode: {name:'Command Code', icon:'commandcode.svg', type:'key'},
 codebuff: {name:'Codebuff', icon:'extension.svg', type:'key'},
 zoommate: {name:'ZoomMate', icon:'extension.svg', type:'key'},
 openaiapi: {name:'OpenAI API', icon:'openai.svg', type:'key'},
 llmproxy: {name:'LLM API Key Proxy', icon:'extension.svg', type:'key', needsAddress:true},
 bifrost: {name:'Bifrost', icon:'extension.svg', type:'key', needsAddress:true},
 hyper: {name:'Hyper', icon:'extension.svg', type:'key'},
 amp: {name:'Amp', icon:'amp.svg', type:'key'},
 v0: {name:'v0', icon:'v0.svg', type:'key'},
 gitkraken: {name:'GitKraken AI', icon:'extension.svg', type:'key'},
 manus: {name:'Manus', icon:'manus.svg', type:'key'},
 qoder: {name:'Qoder', icon:'qoder.svg', type:'key'},
 alibabatoken: {name:'Alibaba Token Plan', icon:'alibabacloud.svg', type:'local'},
 dimagent: {name:'DimAgent', icon:'dimagent.svg', type:'local'},
 xkiro: {name:'xKiro', icon:'extension.svg', type:'key'},
 windsurf: {name:'Windsurf', icon:'windsurf.svg', type:'key'},
 typesafe: {name:'TypeSafe', icon:'extension.svg', type:'key'},
 zed: {name:'Zed', icon:'extension.svg', type:'key'},
 perplexity: {name:'Perplexity', icon:'perplexity.svg', type:'key'},
 poe: {name:'Poe', icon:'poe.svg', type:'key'},
 opendesign: {name:'Open Design', icon:'opendesign.svg', type:'key'},
 sakana: {name:'Sakana AI', icon:'sakana.svg', type:'key'},
 devin: {name:'Devin', icon:'devin.svg', type:'key'},
 raycastai: {name:'Raycast AI', icon:'extension.svg', type:'key'},
 ibmbob: {name:'IBM Bob', icon:'ibm.svg', type:'key'},
 augment: {name:'Augment Code', icon:'extension.svg', type:'key'},
 jetbrainsai: {name:'JetBrains AI', icon:'extension.svg', type:'local'},
 grok: {name:'Grok', icon:'grok.svg', type:'local'},
 grokbot: {name:'Grok Bot', icon:'grok.svg', type:'local'},
 gemini: {name:'Gemini CLI', icon:'geminicli.svg', type:'local'},
 notionai: {name:'Notion AI', icon:'notion.svg', type:'key'},
 v2ex: {name:'V2EX', icon:'v2ex.svg', type:'key'},
 ollamacloud: {name:'Ollama Cloud', icon:'ollama.svg', type:'key'},
 qwencloud: {name:'Qwen Cloud', icon:'qwen.svg', type:'key'},
 sub2api: {name:'sub2api', icon:'sub2api.svg', type:'key', needsAddress:true},
 newapi: {name:'New API', icon:'newapi.svg', type:'key', needsAddress:true},
 litellm: {name:'LiteLLM', icon:'extension.svg', type:'key', needsAddress:true},
 alibabacoding: {name:'Alibaba Coding Plan', icon:'alibabacloud.svg', type:'key'},
 clawrouter: {name:'ClawRouter', icon:'openclaw.svg', type:'key'},
 stepfun: {name:'StepFun', icon:'stepfun.svg', type:'key'},
 xiaomi: {name:'Xiaomi Coding Plan', icon:'xiaomimimo.svg', type:'key'},
 mistral: {name:'Mistral', icon:'mistral.svg', type:'key'},
 longcat: {name:'LongCat', icon:'longcat.svg', type:'key'},
 replicate: {name:'Replicate', icon:'replicate.svg', type:'key'},
 t3chat: {name:'T3 Chat', icon:'extension.svg', type:'key'},
 opencode: {name:'OpenCode Go', icon:'opencode.svg', type:'key'},
 kimi: {name:'Kimi Code', icon:'kimi.svg', type:'key'},
 deepseek: {name:'DeepSeek', icon:'deepseek.svg', type:'key'},
 elevenlabs: {name:'ElevenLabs', icon:'elevenlabs.svg', type:'key'},
 synthetic: {name:'Synthetic', icon:'extension.svg', type:'key'},
 zai: {name:'Z.ai', icon:'zai.svg', type:'key'},
 glm: {name:'智谱 GLM Coding Plan', icon:'zai.svg', type:'key'}
};
function retryableNetworkError(error){const code=String(error?.cause?.code??error?.code??''),message=String(error?.message??'');return error?.name==='TimeoutError'||error?.cause?.name==='TimeoutError'||/^(?:ECONNRESET|ECONNREFUSED|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|ERR_CONNECTION_RESET|ERR_CONNECTION_CLOSED|ERR_CONNECTION_TIMED_OUT|ERR_CONNECTION_REFUSED|ERR_NAME_NOT_RESOLVED|ERR_INTERNET_DISCONNECTED)$/.test(code)||/net::ERR_(?:CONNECTION_RESET|CONNECTION_CLOSED|CONNECTION_TIMED_OUT|CONNECTION_REFUSED|NAME_NOT_RESOLVED|INTERNET_DISCONNECTED)\b/.test(message)}
async function request(url, headers, options={}) {
 // Electron's network stack follows the Windows system proxy and validates TLS.
 // Redirects are forbidden so a credential is never forwarded to another origin.
 require('./network-config').ensureReady();const {net} = require('electron');
 let response;
 try { response=await net.fetch(url,{headers,method:options.method??'GET',body:options.body,credentials:'omit',redirect:'error',signal:AbortSignal.timeout(Number.isFinite(options.timeoutMs)?Math.max(1,Math.min(options.timeoutMs,20000)):20000)}); }
 catch (error) { require('./response-log').record(url,headers,options,null,'无法连接服务商');const result=new Error('无法连接服务商，请检查网络或代理设置');result.retryable=retryableNetworkError(error);throw result; }
 const length=Number(response.headers.get('content-length'));
 if(length>2_000_000) throw new Error('响应过大');
 if(options.responseBytes){const bytes=Buffer.from(await response.arrayBuffer());require('./response-log').record(url,headers,options,response,bytes);if(bytes.length>2_000_000)throw new Error('响应过大');if(response.status!==200){const err=new Error(`服务商返回 HTTP ${response.status}`);err.status=response.status;throw err;}return bytes;}
 const body=await response.text();require('./response-log').record(url,headers,options,response,body); if(body.length>2_000_000) throw new Error('响应过大');
 if(response.status!==200){const err=new Error(`服务商返回 HTTP ${response.status}`);err.status=response.status;try{err.errorType=JSON.parse(body)?.error?.type}catch{}if(/^https:\/\/cloudcode-pa\.googleapis\.com\/v1internal:(?:loadCodeAssist|retrieveUserQuota)$/.test(url)&&/unsupported_client|ineligibletiererror/i.test(body))err.unsupportedClient=true;throw err;}
 if(options.expectedResponse)require('./response-validation').validate(response,options.expectedResponse);
 if(options.responseText)return body;try { return JSON.parse(body); } catch { throw new Error('服务商返回了无法读取的数据'); }
}
async function codexAuth() {
 const roots=[process.env.CODEX_HOME,path.join(os.homedir(),'.codex')].filter(Boolean);
 for (const root of roots) { try {const auth=JSON.parse(await fs.readFile(path.join(root,'auth.json'),'utf8')); if(auth.tokens?.access_token)return auth.tokens;}catch(e){if(e.code!=='ENOENT' && !(e instanceof SyntaxError)) throw new Error('无法读取 Codex 登录文件');} }
 throw new Error('找不到 Codex 登录信息，请先登录 Codex');
}
async function fetchCursor(cookie,transport) {
 const headers={Cookie:cookie,Accept:'application/json'}, postHeaders={...headers,'Content-Type':'application/json',Origin:'https://cursor.com'};
 const summary=await transport('https://cursor.com/api/usage-summary',headers);let plan=null,period=null;
 try{plan=await transport('https://cursor.com/api/dashboard/get-plan-info',postHeaders,{method:'POST',body:'{}'});}catch{}
 const v=plan?.planInfo?.includedUsagePeriod,weekly=v===2||['INCLUDED_USAGE_PERIOD_WEEKLY','WEEKLY'].includes(String(v??'').toUpperCase());
 if(weekly)period=await transport('https://cursor.com/api/dashboard/get-current-period-usage',postHeaders,{method:'POST',body:'{}'});
 const data=require('./cursor-parser').cursor(summary,plan,period);if(!data.windows.length)throw new Error('服务商未报告可显示的额度');return data;
}
async function fetchProvider(id, key, transport=request, options={}) {
 let data;
 if(id==='volcengine')data=await require('./volcengine').fetchVolcengine(key,transport,{...options.volcengineOptions,source:options.volcengineSource});
 else if(id==='kiro')data=await require('./kiro').fetchKiro(options.kiroOptions);
 else if(id==='commandcode')data=await require('./command-code').fetchCommandCode(key,transport,options.commandCodeHome);
 else if(id==='qoder')data=await require('./qoder').fetchQoder(key,options.site,transport,options.qoderShowsParts);
 else if(id==='alibabatoken')data=await require('./alibaba-token').fetchAlibabaToken(options.alibabaOptions);
 else if(id==='dimagent')data=await require('./dimagent').fetchDim(options.dimOptions);
 else if(id==='xkiro')data=await require('./xkiro').fetchXKiro(key,transport);
 else if(id==='windsurf')data=await require('./windsurf').fetchWindsurf(key,transport);
 else if(id==='typesafe')data=await require('./typesafe').fetchTypeSafe(key,transport);
 else if(id==='zed')data=await require('./zed').fetchZed(key,transport);
 else if(id==='perplexity')data=await require('./perplexity').fetchPerplexity(key,transport);
 else if(id==='poe')data=await require('./poe').fetchPoe(key,transport);
 else if(id==='opendesign')data=await require('./open-design').fetchOpenDesign(key,transport,options.openDesignHome);
 else if(id==='sakana')data=await require('./sakana').fetchSakana(key,transport);
 else if(id==='devin')data=key?await require('./devin-live').fetchLive(key,transport):require('./devin').fetchDevin(options.devinRoaming,options.now);
 else if(id==='raycastai')data=await require('./raycast-ai').fetchRaycast(key,transport);
 else if(id==='ibmbob')data=await require('./ibm-bob').fetchIBM(key,transport);
 else if(id==='augment')data=await require('./augment').fetchAugment(key,transport);
 else if(id==='jetbrainsai')data=await require('./jetbrains-ai').fetchJetBrains(options.jetbrainsRoaming,options.now);
 else if(id==='grok')data=await require('./grok').fetchGrok(transport,options.grokHome,options.now,options.grokAccessToken);
 else if(id==='grokbot')data=await require('./grok-bot').fetchGrokBot(transport,options.cursorLogin);
 else if(id==='gemini')data=await require('./gemini').fetchGemini(transport,options.geminiHome,options.now);
 else if(id==='notionai')data=await require('./notion-ai').fetchNotion(key,transport);
 else if(id==='v2ex')data=await require('./v2ex').fetchV2EX(key,transport);
 else if(id==='ollamacloud')data=await require('./ollama-cloud').fetchOllama(key,transport);
 else if(id==='qwencloud')data=await require('./qwen-cloud').fetchQwen(key,transport);
 else if(id==='sub2api')data=await require('./sub2api').fetchSub2API(options.address,key,transport);
 else if(id==='newapi')data=await require('./newapi').fetchNewAPI(options.address,key,transport);
 else if(id==='litellm')data=await require('./litellm').fetchLiteLLM(options.address,key,transport);
 else if(id==='alibabacoding')data=await require('./alibaba-coding').fetchAlibaba(key,transport);
 else if(id==='clawrouter')data=await require('./clawrouter').fetchClawRouter(key,transport);
 else if(id==='stepfun')data=await require('./stepfun').fetchStepFun(key,options.site,transport);
 else if(id==='xiaomi')data=await require('./xiaomi').fetchXiaomi(key,transport);
 else if(id==='mistral')data=await require('./mistral').fetchMistral(key,transport);
 else if(id==='longcat')data=await require('./longcat').fetchLongCat(key,transport);
 else if(id==='replicate')data=await require('./replicate').fetchReplicate(key,transport);
 else if(id==='antigravity')data=await require('./antigravity').fetchAntigravity();
 else if(id==='cursor') {
  const auth=require('./cursor-auth');const {safeStorage}=require('electron');const cookie=auth.readCursorSession(auth.defaultPath(),data=>safeStorage.decryptString(data));
  data=await fetchCursor(cookie,transport);
 }
 else if(id==='claude')data=options.claudeAccessToken?await require('./claude-code').fetchClaudeWithToken(options.claudeAccessToken,transport,options.claudePlanCache):await require('./claude-code').fetchClaude(transport,{...options.claudeOptions,source:options.claudeSource??options.claudeOptions?.source});
 else if(id==='codex') {
 const source=options.codexSource??'automatic';if(!['automatic','endpoint','tooling'].includes(source))throw Error('无效的 Codex 读取方式');
 if(source!=='tooling'){let t;try{t=await require('./response-log').attempt('endpointCredentials',()=> (options.codexAuth??codexAuth)())}catch(e){if(source==='endpoint')throw e}if(!t&&source==='endpoint')throw Error('找不到 Codex 登录信息，请先登录 Codex');
 if(t){const h={Authorization:'Bearer '+t.access_token,Accept:'application/json'};if(t.account_id)h['ChatGPT-Account-Id']=t.account_id;try{data=await require('./response-log').attempt('endpoint',async()=>{for(let attempt=0;;attempt++){try{return {...parsers.codex(await transport('https://chatgpt.com/backend-api/wham/usage',h)),source:'oauth'}}catch(e){if(!e.retryable||attempt>=2)throw e;const delay=Number.isFinite(options.codexRetryDelayMs)?Math.max(0,options.codexRetryDelayMs):600;if(delay)await new Promise(r=>setTimeout(r,delay*(attempt+1)))}}});}catch(e){if(source==='endpoint'||(e.status!==401&&e.status!==403))throw e;}}}
 if(!data)data=await require('./response-log').attempt('appServer',async()=>({...await (options.codexServer??require('./codex-server').readLimits)(),source:'appServer'}));
 }
 else if(id==='t3chat')data=await require('./t3chat').fetchT3(key,transport);
 else if(id==='gitkraken')data=await require('./agent-providers').fetchGitkraken(key,transport);
 else if(id==='manus')data=await require('./agent-providers').fetchManus(key,transport);
 else if(id==='v0')data=await require('./v0').fetchV0(key,transport);
 else if(id==='amp')data=await require('./amp').fetchAmp(key,transport);
 else if(id==='hyper'){if(!key||!key.trim())throw new Error('请在设置中填写 API 密钥');const reply=await transport('https://hyper.charm.land/v1/credits',{Authorization:`Bearer ${key.trim()}`,Accept:'application/json'});if(typeof reply?.balance!=='number'||!Number.isFinite(reply.balance)||reply.balance<0)throw new Error('服务商返回了无法读取的数据');data={windows:[],displayBalance:{amount:reply.balance,unit:'HC'}};}
 else if(id==='bifrost')data=await require('./bifrost').fetchBifrost(options.address,key,transport);
 else if(id==='llmproxy')data=await require('./gateway').fetchProxy(options.address,key,transport);
 else if(id==='openaiapi')data=await require('./openai-platform').fetchBalance(key,transport);
 else if(id==='zoommate')data=await require('./zoommate').fetchZoommate(key,transport);
 else if(id==='codebuff')data=await require('./codebuff').fetchCodebuff(key,transport,options.codebuffHome);
 else if(id==='abacus')data=await require('./abacus').fetchAbacus(key,transport);
 else if(id==='zenmux')data=await require('./plans-extra').fetchZenmux(key,transport);
 else if(id==='devpass'){if(!key||!key.trim())throw new Error('请在设置中填写 API 密钥');data=require('./plans-extra').devpass(await transport('https://api.llmgateway.io/v1/key',{Authorization:`Bearer ${key.trim()}`,Accept:'application/json'}));}
 else if(id==='aixy'){if(!key||!key.trim())throw new Error('请在设置中填写 API 密钥');data=require('./aixy').parseAixy(await transport('https://api.aixy-gateway.com/v1/usage',{Authorization:`Bearer ${key.trim()}`,Accept:'application/json'}));}
 else if(id==='copilot')data=await require('./copilot').fetchCopilot(key,transport);
 else if(id==='nous')data=await require('./nous').fetchNous(transport,options.nousHome,options.now);
 else if(id==='venice'){if(!key||!key.trim())throw new Error('请在设置中填写 API 密钥');data=require('./venice').parseVenice(await transport('https://api.venice.ai/api/v1/billing/balance',{Authorization:`Bearer ${key.trim()}`,Accept:'application/json'}));}
 else if(id==='xai')data=await require('./xai').fetchBalance(key,transport);
 else if(id==='huggingface')data=await require('./huggingface').fetchQuota(key,transport,options.hfHome);
 else if(id==='moonshot')data=await require('./moonshot').fetchMoonshot(key,transport);
 else if(id==='factory') {if(!key||!key.trim())throw new Error('请在设置中填写 API 密钥');data=await require('./factory').fetchFactory(key.trim(),transport);}
 else if(id==='warp') {
  if(!key||!key.trim())throw new Error('请在设置中填写 API 密钥');const version=os.release();const query='query GetRequestLimitInfo($requestContext: RequestContext!) { user(requestContext: $requestContext) { __typename ... on UserOutput { user { requestLimitInfo { isUnlimited nextRefreshTime requestLimit requestsUsedSinceLastRefresh } bonusGrants { requestCreditsGranted requestCreditsRemaining expiration } workspaces { bonusGrantsInfo { grants { requestCreditsGranted requestCreditsRemaining expiration } } } } } } }';
  const body=JSON.stringify({operationName:'GetRequestLimitInfo',query,variables:{requestContext:{clientContext:{},osContext:{category:'Windows',name:'Windows',version}}}});data=parsers.warp(await transport('https://app.warp.dev/graphql/v2?op=GetRequestLimitInfo',{Authorization:'Bearer '+key.trim(),'Content-Type':'application/json','x-warp-client-id':'warp-app','x-warp-os-category':'Windows','x-warp-os-name':'Windows','x-warp-os-version':version,'User-Agent':'Warp/1.0'},{method:'POST',body}));
 }
 else if(id==='kilo') {
  if(!key){try {const auth=JSON.parse(await fs.readFile(path.join(os.homedir(),'.local','share','kilo','auth.json'),'utf8'));key=auth.kilo?.access;}catch(e){if(e.code!=='ENOENT'&&!(e instanceof SyntaxError))throw new Error('无法读取 Kilo 登录文件');}}
  if(!key||!key.trim())throw new Error('请在设置中填写 API 密钥');
  const url=new URL('https://app.kilo.ai/api/trpc/user.getCreditBlocks,kiloPass.getState');url.searchParams.set('batch','1');url.searchParams.set('input',JSON.stringify({'0':{json:null},'1':{json:null}}));
  data=parsers.kilo(await transport(url.toString(),{Authorization:`Bearer ${key.trim()}`,Accept:'application/json'}));
 }
 else if(id==='minimax') {
  if(!key||!key.trim())throw new Error('请在设置中填写 API 密钥');
  if(!['international','china'].includes(options.site))throw new Error('请选择 MiniMax 站点');
  const host=options.site==='china'?'https://api.minimaxi.com':'https://api.minimax.io';let firstError;
  for(const route of ['/v1/token_plan/remains','/v1/api/openplatform/coding_plan/remains']) {try{data=parsers.minimax(await transport(host+route,{Authorization:`Bearer ${key.trim()}`,Accept:'application/json'}));if(data.windows.length)break;throw new Error('服务商未报告可显示的额度');}catch(e){firstError??=e;}}
  if(!data?.windows?.length)throw firstError;
 }
 else if(id==='opencode') {
  if(!key){try {const auth=JSON.parse(await fs.readFile(path.join(os.homedir(),'.local','share','opencode','auth.json'),'utf8'));key=auth['opencode-go']?.key;}catch(e){if(e.code!=='ENOENT' && !(e instanceof SyntaxError))throw new Error('无法读取 OpenCode 登录文件');}}
  let failure=null;if(key?.trim()){try{data=parsers.opencode(await transport('https://opencode.ai/zen/go/v1/usage',{Authorization:'Bearer '+key.trim(),Accept:'application/json'}))}catch(e){if(e.status===429)throw e;failure=e.status===403&&e.errorType==='EntitlementError'?Error('账号没有 OpenCode Go 订阅'):e}}
  if(!data&&options.opencodeConsoleCookie){try{data=await require('./opencode-console').fetchStatus(options.opencodeConsoleCookie,transport)}catch(e){if(!key?.trim())throw e}}if(!data)throw failure??Error('请在设置中填写 API 密钥或读取 OpenCode 控制台登录');
 }
 else if(id==='deepseek'){const consoleToken=options.deepseekConsoleToken;let failure=null;if(key?.trim()){try{const parsed=parsers.deepseek(await transport('https://api.deepseek.com/user/balance',{Authorization:'Bearer '+key.trim(),Accept:'application/json'}));if(!parsed.balances?.length)throw Error('DeepSeek 未报告余额');data={...parsed,source:'apiKey'}}catch(e){if(e.status===429)throw e;failure=e}}if(!data&&consoleToken){try{data=await require('./deepseek-console').renewing(consoleToken,token=>require('./deepseek-console').fetchBalance(token,transport),options.renewDeepseekConsole)}catch(e){if(!key?.trim())throw e}}if(!data)throw failure??Error('请在设置中填写 API 密钥或登录 DeepSeek 控制台');}
 else if(['kimi','elevenlabs','synthetic','zai','glm','cline','chutes','deepinfra','vercel','atlas','neuralwatt'].includes(id)) {
  const endpoints={atlas:'https://api.atlascloud.ai/public/v1/balance',neuralwatt:'https://api.neuralwatt.com/v1/quota',deepinfra:'https://api.deepinfra.com/payment/checklist?compute_owed=true',vercel:'https://ai-gateway.vercel.sh/v1/credits',chutes:'https://api.chutes.ai/users/me/subscription_usage',cline:'https://api.cline.bot/api/v1/users/me/plan/usage-limits',kimi:'https://api.kimi.com/coding/v1/usages',deepseek:'https://api.deepseek.com/user/balance',elevenlabs:'https://api.elevenlabs.io/v1/user/subscription',synthetic:'https://api.synthetic.new/v2/quotas',zai:'https://api.z.ai/api/monitor/usage/quota/limit',glm:'https://open.bigmodel.cn/api/monitor/usage/quota/limit'};
  if(!key && id==='glm') {for(const name of ['.coding-relay/glm-api-key','.config/bigmodel/api_key','.config/zhipu/api_key']) {try {key=(await fs.readFile(path.join(os.homedir(),name),'utf8')).split(/\r?\n/)[0].trim();if(key)break;} catch(e){if(e.code!=='ENOENT')throw new Error('无法读取 GLM 登录文件');}}}
  if(!key || !key.trim()) throw new Error('请在设置中填写 API 密钥');
  const headers={Accept:'application/json'};if(id==='elevenlabs')headers['xi-api-key']=key.trim();else headers.Authorization=`Bearer ${key.trim()}`;
  data=parsers[id==='glm'?'zai':id](await transport(endpoints[id],headers),id);
 } else throw new Error('未知服务商');
 if(!data.windows.length && !data.balances?.length && !data.displayBalance) throw new Error('服务商未报告可显示的额度或余额');
 return {...data, observedAt:Object.hasOwn(data,'observedAt')?data.observedAt:new Date().toISOString()};
}
module.exports={providers,fetchProvider,fetchCursor,request,retryableNetworkError};
