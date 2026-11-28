const fs=require('node:fs');const path=require('node:path');const {DatabaseSync}=require('node:sqlite');
function sessionFromToken(token,now=Date.now()){
 if(typeof token!=='string')throw new Error('Cursor 登录信息不可用');const parts=token.split('.');if(parts.length!==3)throw new Error('Cursor 登录信息不可用');let claims;try{claims=JSON.parse(Buffer.from(parts[1],'base64url').toString('utf8'));}catch{throw new Error('Cursor 登录信息不可用');}
 const expiry=typeof claims.exp==='number'?claims.exp:Number(claims.exp),account=typeof claims.sub==='string'?claims.sub.split('|').filter(Boolean).at(-1):null;
 if(!account||!Number.isFinite(expiry)||expiry*1000<=now+60000)throw new Error('Cursor 登录已过期，请打开 Cursor 重新登录');
 return `WorkosCursorSessionToken=${encodeURIComponent(account)}%3A%3A${token}`;
}
function readCursorSession(file,decrypt){
 if(!fs.existsSync(file))throw new Error('找不到 Cursor 登录信息，请先登录 Cursor');let db,row;
 try{db=new DatabaseSync(file,{readOnly:true});row=db.prepare('SELECT value FROM ItemTable WHERE key = ?').get('cursorAuth/accessToken');}catch{throw new Error('无法读取 Cursor 登录信息');}finally{db?.close();}
 if(!row?.value)throw new Error('找不到 Cursor 登录信息，请先登录 Cursor');let value=row.value;
 if(value instanceof Uint8Array){const data=Buffer.from(value);value=data.includes(0)?data.toString('utf16le'):data.toString('utf8');}
 if(typeof value!=='string')throw new Error('Cursor 登录信息不可用');const prefix='cursor-safe-storage:v1:';
 if(value.startsWith(prefix)){try{if(!decrypt)throw new Error();value=decrypt(Buffer.from(value.slice(prefix.length),'base64'));}catch{throw new Error('无法解密 Cursor 登录信息，请检查 Cursor 登录状态');}}
 return sessionFromToken(value);
}
function defaultPath(){return path.join(process.env.APPDATA||path.join(require('node:os').homedir(),'AppData','Roaming'),'Cursor','User','globalStorage','state.vscdb');}
module.exports={sessionFromToken,readCursorSession,defaultPath};
