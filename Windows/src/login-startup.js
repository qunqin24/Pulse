// A user-controlled Windows login item for this installation only.
const path=require('node:path');
const name='Pulse.Windows.Development';
function options(app){return {path:process.execPath,args:app.isPackaged?[]:['"'+path.resolve(__dirname,'..')+'"']}}
function read(app){if(process.platform!=='win32')return {supported:false,registered:false,enabled:false};try{const current=app.getLoginItemSettings(options(app)),item=(current.launchItems??[]).find(x=>x.name===name&&x.scope==='user');return {supported:true,registered:!!item,enabled:!!item?.enabled}}catch{return {supported:false,registered:false,enabled:false}}}
function set(app,value){const before=read(app);if(!before.supported)throw Error('无法读取 Windows 启动项');app.setLoginItemSettings({...options(app),name,openAtLogin:value.registered,enabled:value.enabled});const after=read(app);if(!after.supported||after.registered!==value.registered||value.registered&&after.enabled!==value.enabled)throw Error('Windows 未接受启动项设置');return after}
module.exports={name,options,read,set};
