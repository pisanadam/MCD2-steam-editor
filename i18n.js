/* Translate display text only. Never modify inputs, save tokens or game IDs. */
(() => {
'use strict';
const messages=window.DungeonsTranslations||{},nodes=new WeakMap(),attributes=new WeakMap();
let language='en',revision=0,queued=false,hostLoaded=false;
try { const saved=localStorage.getItem('dungeons-forge-language');if(['en','tr'].includes(saved))language=saved; } catch {}
const escape=s=>s.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
const keys=Object.keys(messages).sort((a,b)=>b.length-a.length);
const matcher=new RegExp(keys.map(escape).join('|'),'g');
function translate(text){return language==='tr'?text:text.replace(matcher,key=>messages[key]);}
function render(){
 queued=false;
 const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,{acceptNode(node){return node.parentElement?.closest('script,style,.native-code,.native-field small')?NodeFilter.FILTER_REJECT:NodeFilter.FILTER_ACCEPT}});
 while(walker.nextNode()){
  const node=walker.currentNode;let state=nodes.get(node);
  if(!state||node.nodeValue!==state.rendered)state={source:node.nodeValue,rendered:node.nodeValue};
  const result=translate(state.source);state.rendered=result;nodes.set(node,state);if(node.nodeValue!==result)node.nodeValue=result;
 }
 for(const element of document.querySelectorAll('[placeholder],[title],[aria-label],[alt]')){
  if(element.closest('script,style,.native-code,.native-field small'))continue;
  let state=attributes.get(element);if(!state){state={};attributes.set(element,state)}
  for(const name of ['placeholder','title','aria-label','alt'])if(element.hasAttribute(name)){
   const value=element.getAttribute(name);if(!state[name]||state[name].rendered!==value)state[name]={source:value,rendered:value};
   const result=translate(state[name].source);state[name].rendered=result;if(value!==result)element.setAttribute(name,result);
  }
 }
 document.documentElement.lang=language;
 document.title=language==='tr'?'Dungeons II Forge — Steam Kayıt Düzenleyici':'Dungeons II Forge — Steam Save Editor';
 const select=document.querySelector('#settings-language');if(select)select.value=language;
}
function schedule(){if(!queued){queued=true;queueMicrotask(render)}}
function setLanguage(value,persist=true){
 if(!['en','tr'].includes(value))throw Error('Unsupported language');language=value;revision++;render();
 if(persist){
  try{localStorage.setItem('dungeons-forge-language',value)}catch{}
  if(window.pywebview?.api?.set_language)window.pywebview.api.set_language(value).then(result=>{if(result.error)toast('Dil ayarı kaydedilemedi: '+result.error)}).catch(()=>toast('Dil ayarı kaydedilemedi.'));
 }
}
async function loadHostSettings(){
 if(hostLoaded||!window.pywebview?.api?.get_settings)return;hostLoaded=true;const before=revision;
 try{const settings=await window.pywebview.api.get_settings();if(revision===before&&['en','tr'].includes(settings.language))setLanguage(settings.language,false)}catch{}
}
const button=document.createElement('button');button.id='settings-open';button.textContent='Ayarlar';document.querySelector('aside .aside-bottom').before(button);
button.onclick=()=>{
 let dialog=document.querySelector('#settings-dialog');if(dialog){dialog.showModal();return}
 dialog=document.createElement('dialog');dialog.id='settings-dialog';dialog.innerHTML='<h2>Ayarlar</h2><label for="settings-language">Dil</label><select id="settings-language"><option value="en">English</option><option value="tr">Türkçe</option></select><p class="muted">Dil seçimin bir sonraki açılış için hatırlanır.</p><button id="settings-close">Kapat</button>';
 document.body.append(dialog);dialog.querySelector('select').onchange=e=>setLanguage(e.target.value);dialog.querySelector('button').onclick=()=>dialog.close();render();dialog.showModal();
};
new MutationObserver(schedule).observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['placeholder','title','aria-label','alt']});
window.addEventListener('pywebviewready',loadHostSettings);
window.DungeonsI18n={setLanguage,getLanguage:()=>language,render,loadHostSettings};render();loadHostSettings();
})();
