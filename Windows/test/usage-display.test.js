const test=require('node:test');const assert=require('node:assert/strict');const {values}=require('../src/usage-display');
test('usage and remaining display count in opposite directions without changing warning basis',()=>{
 assert.deepEqual(values({usedPercent:35},false),{used:35,figure:35,arc:35});
 assert.deepEqual(values({usedPercent:35},true),{used:35,figure:65,arc:65});
 assert.deepEqual(values({usedPercent:100},true),{used:100,figure:0,arc:100});
 assert.deepEqual(values({usedPercent:20,exhausted:true},true),{used:20,figure:80,arc:100});
 assert.equal(values(null,true),null);
});
test('displayed quota counts use reported amounts and the selected direction',()=>{const {amount}=require('../src/usage-display');const w={amounts:{used:127.4,remaining:72.6,limit:200}};assert.equal(amount(w,false),'127.4 / 200');assert.equal(amount(w,true),'72.6 / 200');assert.equal(amount({amounts:{used:1}},false),null);});
test('headline is fullest, and second prefers the same scope',()=>{
 const {select}=require('../src/usage-display');const a={usedPercent:70,scope:'Gemini'},b={usedPercent:20,scope:'Gemini'},c={usedPercent:60,scope:'Claude'};assert.deepEqual(select([a,b,c]),{headline:a,second:b});assert.deepEqual(select([a,c]),{headline:a,second:c});assert.equal(select([{usedPercent:12},{usedPercent:12}]).headline.usedPercent,12);assert.equal(select([]).second,null);
});
test('clock requires a stated length and reset, and supports both directions',()=>{const {clock}=require('../src/usage-display');const w={reportsLength:true,seconds:100,reset:'2026-01-01T00:01:40Z'},now=Date.parse('2026-01-01T00:00:25Z');assert.equal(clock(w,'elapsed',now),0.25);assert.equal(clock(w,'remaining',now),0.75);assert.equal(clock({...w,reportsLength:false},'elapsed',now),null);assert.equal(clock({...w,reset:null},'elapsed',now),null);assert.equal(clock(w,'off',now),null);});
test('displayed percentages preserve nonzero and not-full at both extremes',()=>{const {percent}=require('../src/usage-display');assert.equal(percent(0),0);assert.equal(percent(0.03),1);assert.equal(percent(99.9),99);assert.equal(percent(100),100);assert.equal(percent(NaN),0);});
