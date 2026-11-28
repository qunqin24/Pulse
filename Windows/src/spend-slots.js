const pricing=require('./model-pricing');
function add(slots,timestamp,model,tally,context=0,hourWrite=0){const at=Date.parse(timestamp);if(!Number.isFinite(at)||typeof model!=='string'||!model)return;const key=String(Math.floor(at/900000)*900000),bucket=slots[key]??(slots[key]=Object.create(null)),entry=bucket[model]??(bucket[model]=pricing.empty());pricing.add(entry,tally,context,hourWrite)}
module.exports={add};
