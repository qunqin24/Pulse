// Original Pulse scale and rail-spacing choices.
(function(root){const sizes={small:.82,standard:1,large:1.22},spacings={compact:.6,standard:1,roomy:1.4};function values(size,spacing){return {scale:sizes[size]??1,spacing:spacings[spacing]??1}}const api={sizes,spacings,values};if(typeof module!=='undefined')module.exports=api;else root.panelAppearance=api})(globalThis);
