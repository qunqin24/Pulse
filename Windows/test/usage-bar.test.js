const test=require('node:test'),assert=require('node:assert/strict'),{ticks}=require('../src/usage-bar');
test('segmented bars fit original tick dimensions and scale',()=>{assert.equal(ticks(200,0).count,44);assert.equal(ticks(200,0,2).count,22);assert.equal(ticks(0,.5).count,1)});
test('segmented bars light at least one after use and all only at full',()=>{assert.deepEqual([0,.001,.5,.999,1,1.4,-1].map(f=>ticks(200,f).lit),[0,1,22,43,44,44,0])});
