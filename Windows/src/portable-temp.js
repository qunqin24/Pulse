const path=require('node:path'),os=require('node:os');
exports.folder=name=>path.join(process.env.LOCALAPPDATA||os.tmpdir(),'Pulse-Windows','Temp',name);
