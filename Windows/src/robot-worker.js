// The renderer runs away from the rail's UI thread; frames are never persisted.
importScripts('open-bot-avatar.js','open-bot-gallery.js','robot-engine.js');
const engine=pulseRobotEngine.create(OpenBotAvatar,PulseBotGallery);
self.onmessage=event=>{const request=event.data;if(!request||typeof request.key!=='string')return;if(request.kind==='forget'){engine.forget(request.key);return}if(request.kind!=='frame'||typeof request.id!=='string')return;try{const frame=engine.frame(request.key,request.id,request.options);self.postMessage({key:request.key,sequence:request.sequence,frame})}catch{self.postMessage({key:request.key,sequence:request.sequence,frame:null})}};
