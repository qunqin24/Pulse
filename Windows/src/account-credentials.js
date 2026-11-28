// Isolated added-account credential operations; encryption is supplied by the main process.
function encode(value,encrypt){if(typeof encrypt!=='function')throw Error('系统加密服务不可用');const bytes=encrypt(JSON.stringify(value));if(!Buffer.isBuffer(bytes)||!bytes.length)throw Error('无法加密账户凭据');return bytes.toString('base64')}
function read(state,id,decrypt){const encoded=state?.accountLogins?.[id];if(encoded===undefined)return null;if(typeof encoded!=='string'||!encoded||encoded.length>1000000||typeof decrypt!=='function')throw Error('无法读取账户凭据');let result;try{result=JSON.parse(decrypt(Buffer.from(encoded,'base64')))}catch{throw Error('无法解密账户凭据')}if(!result||typeof result.accessToken!=='string'||!result.accessToken||typeof result.refreshToken!=='string'||!Number.isFinite(result.expiresAt))throw Error('账户凭据无效');return result}
function put(state,id,value,encrypt){return {...state,accountLogins:{...(state.accountLogins??{}),[id]:encode(value,encrypt)}}}
function remove(state,id){const accountLogins={...(state.accountLogins??{})};delete accountLogins[id];return {...state,accountLogins}}
function renew(state,id,expected,value,encrypt){if(typeof expected!=='string'||!expected||state.accountLogins?.[id]!==expected)return null;return put(state,id,value,encrypt)}
module.exports={read,put,remove,renew};
