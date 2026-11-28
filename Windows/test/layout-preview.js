const {app}=require('electron');app.setPath('userData',require('node:path').join(require('node:os').tmpdir(),'Pulse-LayoutTest'));require('../src/main');
