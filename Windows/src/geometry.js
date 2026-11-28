// Geometry shared by the Windows rail and detail bubble, in device-independent pixels.
const clamp=(n,min,max)=>Math.max(min,Math.min(n,max));
const appearance=require('./panel-appearance');
const horizontal=position=>position==='top'||position==='bottom';
function railBounds(work,count,position,collapsed,size='standard',spacing='standard',roundEnds=false,options={}){
 const {scale,spacing:gap}=appearance.values(size,spacing),figures=horizontal(position)?!!options.acrossFigures:options.sideFigures!==false,beside=horizontal(position)&&figures&&!!options.floating&&!!options.figuresBeside,clock=options.clockMode&&options.clockMode!=='off',itemHeight=36+6+(clock?5:0)+16,cross=horizontal(position)&&figures&&!beside?itemHeight+(options.floating?28:20)+(clock?10:0):64,thickness=Math.round(cross*scale),padding=(roundEnds?60:44)*scale;
 if(horizontal(position)){
  const expanded=Math.min(Math.max(110*scale,(count*(beside?36+6+(clock?5:0)+38:figures?38:36)+Math.max(0,count-1)*(beside?18:options.floating&&figures?20:30)*gap)*scale+padding),Math.max(32,work.width-16));
  const width=collapsed?Math.min(Math.round(96*scale),Math.max(1,work.width-16)):Math.round(expanded),height=collapsed?Math.max(1,Math.round(6*scale)):thickness;
  return {x:work.x+Math.round((work.width-width)/2),y:position==='top'?work.y:work.y+work.height-height,width,height};
 }
 const expanded=Math.round(Math.min(Math.max(110*scale,(count*(figures?itemHeight:36)+Math.max(0,count-1)*30*gap)*scale+padding),Math.max(32,work.height-16))),height=collapsed?Math.min(Math.round(96*scale),Math.max(1,work.height-16)):expanded;const width=collapsed?Math.max(1,Math.round(6*scale)):thickness;
 return {x:position==='left'?work.x:work.x+work.width-width,y:work.y+Math.round((work.height-height)/2),width,height};
}
function cardBounds(work,rail,side,anchor,preferredHeight=340,scale=1){
 scale=Number.isFinite(scale)&&scale>0?scale:1;
 const requested=Number.isFinite(preferredHeight)?Math.max(100,Math.ceil(preferredHeight)):340;
 if(horizontal(side)){
  const width=Math.min(Math.round(250*scale),Math.max(1,work.width-16)),height=Math.min(requested,Math.max(1,Math.floor(work.height*.75)),Math.max(1,work.height-rail.height-10));
  const x=clamp(Math.round(anchor-width/2),work.x,work.x+work.width-width),y=side==='top'?rail.y+rail.height:rail.y-height;
  return {x,y:clamp(y,work.y,work.y+work.height-height),width,height};
 }
 const width=Math.min(Math.round(270*scale),Math.max(1,work.width-rail.width-10)),height=Math.min(requested,Math.max(1,Math.floor(work.height*.75)),Math.max(1,work.height-16));
 const y=clamp(Math.round(anchor-height/2),work.y,work.y+work.height-height),x=side==='left'?rail.x+rail.width:rail.x-width;
 return {x:clamp(x,work.x,work.x+work.width-width),y,width,height};
}
function dashboardBounds(work,anchor,height,width=320){const w=Math.min(width,Math.max(1,work.width)),h=Math.max(1,Math.min(Math.ceil(height),580,work.height)),x=clamp(anchor.x+anchor.width-w,work.x,work.x+work.width-w),bottom=anchor.y>=work.y+work.height/2,y=clamp(bottom?anchor.y-h:anchor.y+anchor.height,work.y,work.y+work.height-h);return {x,y,width:w,height:h}}
function displayFor(displays,currentId,primaryId,activeId,follow){if(!Array.isArray(displays)||!displays.length)return null;const find=id=>displays.find(d=>String(d.id)===String(id));return (follow&&activeId!=null?find(activeId):null)||find(currentId)||find(primaryId)||displays[0]}
function contains(rect,p,margin=0){return p.x>=rect.x-margin&&p.x<rect.x+rect.width+margin&&p.y>=rect.y-margin&&p.y<rect.y+rect.height+margin;}

function placedBounds(work,count,position,collapsed,size,spacing,placement,roundEnds=false,options={}){const args={...options,floating:placement?.mode==='floating'},base=railBounds(work,count,position,collapsed,size,spacing,roundEnds&&placement?.mode!=='floating',args);if(!placement||!Number.isFinite(placement.x)||!Number.isFinite(placement.y))return base;const full=collapsed&&placement.mode!=='floating'?railBounds(work,count,position,false,size,spacing,roundEnds,args):base,x=work.x+Math.round(clamp(placement.x,0,1)*Math.max(0,work.width-full.width)),y=work.y+Math.round(clamp(placement.y,0,1)*Math.max(0,work.height-full.height)),centerX=clamp(Math.round(x+(full.width-base.width)/2),work.x,work.x+work.width-base.width),centerY=clamp(Math.round(y+(full.height-base.height)/2),work.y,work.y+work.height-base.height);return {...base,x:placement.mode==='floating'||horizontal(position)?centerX:base.x,y:placement.mode==='floating'||!horizontal(position)?centerY:base.y}}
function collapsedHitBounds(bounds,position,scale=1){const across=Math.max(1,Math.round(20*scale));if(horizontal(position))return {...bounds,y:position==='top'?bounds.y:bounds.y+bounds.height-across,height:across};return {...bounds,x:position==='left'?bounds.x:bounds.x+bounds.width-across,width:across}}
function collapsedWindowBounds(visual,position,scale=1){const span=Math.max(32,Math.round(20*scale));if(horizontal(position))return {...visual,y:position==='top'?visual.y:visual.y+visual.height-span,height:span};return {...visual,x:position==='left'?visual.x:visual.x+visual.width-span,width:span}}
function windowShape(window,visual){return [{x:visual.x-window.x,y:visual.y-window.y,width:visual.width,height:visual.height}]}
function collapsedVisualBounds(window,position,scale=1){const span=Math.max(1,Math.round(6*scale));if(horizontal(position))return {...window,y:position==='top'?window.y:window.y+window.height-span,height:span};return {...window,x:position==='left'?window.x:window.x+window.width-span,width:span}}
function dragPlacement(work,count,point,grab,axis,size,spacing,snaps=true,roundEnds=false,options={}){const d=32,near={top:point.y-work.y,bottom:work.y+work.height-point.y,left:point.x-work.x,right:work.x+work.width-point.x};let position=snaps?(near.top<=d?'top':near.bottom<=d?'bottom':near.left<=d?'left':near.right<=d?'right':null):null;const floating=!position;if(!position)position=axis==='horizontal'?(point.y<work.y+work.height/2?'top':'bottom'):(point.x<work.x+work.width/2?'left':'right');const base=railBounds(work,count,position,false,size,spacing,roundEnds&&!floating,{...options,floating}),changed=horizontal(position)!==(axis==='horizontal'),offsetX=changed?base.width/2:grab.x,offsetY=changed?base.height/2:grab.y,x=clamp(point.x-offsetX,work.x,work.x+work.width-base.width),y=clamp(point.y-offsetY,work.y,work.y+work.height-base.height),ratio=(n,start,span)=>span>0?clamp((n-start)/span,0,1):0;return {position,placement:{mode:floating?'floating':'edge',x:ratio(x,work.x,work.width-base.width),y:ratio(y,work.y,work.height-base.height)}}}
function floatingPlacement(work,bounds,count,axis,size,spacing,options={}){
 const center={x:bounds.x+bounds.width/2,y:bounds.y+bounds.height/2};
 const position=axis==='horizontal'?(center.y<work.y+work.height/2?'top':'bottom'):(center.x<work.x+work.width/2?'left':'right');
 const base=railBounds(work,count,position,false,size,spacing,false,{...options,floating:true}),ratio=(v,start,range)=>range>0?clamp((v-start)/range,0,1):0;
 return {position,placement:{mode:'floating',x:ratio(center.x-base.width/2,work.x,work.width-base.width),y:ratio(center.y-base.height/2,work.y,work.height-base.height)}};
}
module.exports={horizontal,railBounds,cardBounds,contains,dashboardBounds,collapsedHitBounds,collapsedWindowBounds,collapsedVisualBounds,windowShape,displayFor,placedBounds,dragPlacement,floatingPlacement};
