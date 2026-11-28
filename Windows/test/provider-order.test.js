const test=require('node:test');const assert=require('node:assert/strict');const o=require('../src/provider-order');
test('order restores known entries once and appends newly discovered providers',()=>{assert.deepEqual(o.resolve(['b','missing','b','a'],['a','b','c']),['b','a','c']);assert.deepEqual(o.resolve(null,['a','b']),['a','b']);});
test('moving a provider respects list boundaries',()=>{assert.deepEqual(o.move(['a','b','c'],'b',-1),['b','a','c']);assert.deepEqual(o.move(['a','b'],'a',-1),['a','b']);assert.deepEqual(o.move(['a','b'],'missing',1),['a','b']);});

 test('dragging onto another provider preserves the original insertion semantics',()=>{assert.deepEqual(o.moveOnto(['a','b','c'],'a','c'),['b','c','a']);assert.deepEqual(o.moveOnto(['a','b','c'],'c','a'),['c','a','b']);assert.deepEqual(o.moveOnto(['a','b'],'x','a'),['a','b']);assert.deepEqual(o.moveOnto(['a','b'],'a','a'),['a','b']);});

test('moving visible accounts preserves disabled accounts after them',()=>{const all=['a','hidden1','b','hidden2','c'];assert.deepEqual(o.shownOrder(all,o.move(['a','b','c'],'b',-1)),['b','a','c','hidden1','hidden2']);assert.deepEqual(o.shownOrder(all,o.moveOnto(['a','b','c'],'a','c')),['b','c','a','hidden1','hidden2']);});
