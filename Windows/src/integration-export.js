// Export a copy of the bundled integration kit; never overwrite an existing folder.
const fs=require('node:fs'),path=require('node:path');
const omitted=new Set(['node_modules','.git','build','dist','.DS_Store']);
function copyTree(source,target){for(const item of fs.readdirSync(source,{withFileTypes:true})){if(omitted.has(item.name)||item.isSymbolicLink())continue;const from=path.join(source,item.name),to=path.join(target,item.name);if(item.isDirectory()){fs.mkdirSync(to);copyTree(from,to)}else if(item.isFile())fs.copyFileSync(from,to,fs.constants.COPYFILE_EXCL)}}
function exportKit(parent,source=path.join(__dirname,'../integrations')){if(typeof parent!=='string'||!path.isAbsolute(parent)||!fs.statSync(parent).isDirectory())throw Error('请选择有效的文件夹');const target=path.join(parent,'Pulse Integrations');try{fs.mkdirSync(target)}catch(e){if(e.code==='EEXIST')throw Error('目标已存在 Pulse Integrations 文件夹，请选择其他位置');throw e}try{copyTree(source,target)}catch(e){throw Error('导出未完成，部分文件保留在 '+target+'：'+e.message)}return target}
module.exports={exportKit};
