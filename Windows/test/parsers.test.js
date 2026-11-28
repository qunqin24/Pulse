const test=require('node:test'); const assert=require('node:assert/strict'); const fs=require('node:fs'); const path=require('node:path'); const p=require('../src/parsers');
const fixture=n=>JSON.parse(fs.readFileSync(path.join(__dirname,'../../Tests/PulseTests/Fixtures',n),'utf8'));
test('Kimi timed, weekly and monthly windows follow upstream fixtures',()=>{
 let a=p.kimi(fixture('kimi-code-normal.json')); assert.deepEqual(a.windows.map(x=>x.usedPercent),[40,25,70]);
 a=p.kimi(fixture('kimi-code-monthly.json')); assert.deepEqual(a.windows.map(x=>Math.round(x.usedPercent*100)/100),[28,70.23,77.23]);
 assert.equal(p.kimi(fixture('kimi-code-missing-fields.json')).windows.length,0);
});
test('DeepSeek balances stay amounts, not invented quota',()=>{ const a=p.deepseek(fixture('deepseek-two-currencies.json')); assert.deepEqual(a.balances,[{currency:'USD',amount:0},{currency:'CNY',amount:42.3}]); assert.equal(a.windows.length,0); });
test('Codex window is named from duration and missing percent is omitted',()=>{const a=p.codex({rate_limit:{primary_window:{used_percent:12,limit_window_seconds:604800,reset_at:1700000000},secondary_window:{limit_window_seconds:18000}}}); assert.equal(a.windows.length,1); assert.equal(a.windows[0].name,'每周额度');assert.equal(a.windows[0].usedPercent,12);});
test('empty and invalid numeric fields are not zero',()=>{ for(const x of [null,undefined,'',true,'x',Infinity]) assert.equal(p.number(x),null); });
