// Applies the persisted visibility and capture preference to Pulse's own windows.
function applyPanelWindows(rail,card,{visible,ready,hideFromCapture,fullscreenHidden=false}){for(const window of [rail,card])if(window&&!window.isDestroyed())window.setContentProtection(!!hideFromCapture);if(rail&&!rail.isDestroyed()){if(visible&&ready&&!fullscreenHidden)rail.showInactive();else if(!visible||fullscreenHidden){rail.hide();if(card&&!card.isDestroyed())card.hide()}}}
module.exports={applyPanelWindows};
