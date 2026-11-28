// Validates a response before interpreting it as a provider's signed-in page.
function validate(response,expected){if(!expected)return;let actual;try{actual=new URL(response.url)}catch{throw new Error('服务商页面地址无效')}const wanted=new URL(expected.url);if(actual.origin!==wanted.origin||actual.pathname!==wanted.pathname||actual.search||actual.hash)throw new Error('服务商页面地址无效');const type=(response.headers.get('content-type')??'').split(';')[0].trim().toLowerCase();if(type!==expected.contentType)throw new Error('服务商页面类型无效');}
module.exports={validate};
