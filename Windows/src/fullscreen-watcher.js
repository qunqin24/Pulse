// Tracks only the foreground fullscreen monitor; never inspects window titles or keys.
const {spawn}=require('node:child_process'),path=require('node:path'),readline=require('node:readline');
class FullscreenWatcher{
 constructor(onChange,options={}){this.onChange=onChange;this.spawn=options.spawn??spawn;this.process=null;this.generation=0}
 start(){if(this.process||process.platform!=='win32')return;const generation=++this.generation,ps=path.join(process.env.SystemRoot||'C:\\Windows','System32','WindowsPowerShell','v1.0','powershell.exe');let child;try{child=this.spawn(ps,['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',path.join(__dirname,'fullscreen-watch.ps1'),'-OwnerProcessId',String(process.pid)],{windowsHide:true,stdio:['ignore','pipe','ignore']})}catch{return}this.process=child;const lines=readline.createInterface({input:child.stdout});lines.on('line',line=>{if(this.generation!==generation||line.length>128)return;try{const point=JSON.parse(line);if(point===null||Number.isInteger(point?.x)&&Number.isInteger(point?.y)&&Math.abs(point.x)<100000&&Math.abs(point.y)<100000)this.onChange(point)}catch{}});const end=()=>{lines.close();if(this.generation===generation){this.process=null;this.onChange(null)}};child.once('error',end);child.once('exit',end)}
 stop(){this.generation++;const child=this.process;this.process=null;if(child)child.kill();this.onChange(null)}
}
module.exports={FullscreenWatcher};
