/* Only activated inside the standalone Windows host. */
(function(){
function initDungeonsDesktop(){
 if(!window.pywebview?.api||!window.DungeonsNative||document.querySelector('#desktop-find'))return;
 window.DungeonsI18n?.loadHostSettings();
 const api=window.pywebview.api,buttons=document.querySelector('.actions');
 const toB64=bytes=>{let s='';for(let i=0;i<bytes.length;i+=16384)s+=String.fromCharCode(...bytes.subarray(i,i+16384));return btoa(s)};
 let busy=false,canApply=false;
 const notice=document.querySelector('#native-view .notice');
 notice.textContent='Önce Steam kaydını bul ve karakterini aç. Otomatik yedek alınır. Düzenledikten sonra oyun kapalıyken Kaydı oyuna uygula düğmesine bas; ardından oyunda aynı çevrimdışı karakteri yükle.';
 document.querySelector('#help-dialog p').textContent='Steam kaydını bul ile çevrimdışı karakterini seç. Açılışta orijinal kayıt yedeklenir. Düzenle ve oyun kapalıyken Kaydı oyuna uygula düğmesine bas. Ayrı CMD dosyası gerekmez.';
 document.querySelector('.aside-bottom').textContent='Steam kayıtları · Otomatik yedek · Doğrudan oyuna uygula';
 const message=(result)=>{if(result.error)throw Error(result.error);return result};
 async function load(path){const r=message(await api.open_save(path));if(r.cancelled)return;const bytes=Uint8Array.from(atob(r.data),c=>c.charCodeAt(0));DungeonsNative.read(bytes,r.name);canApply=!!r.can_apply;document.querySelector('#desktop-apply').disabled=!canApply;document.querySelector('#desktop-result').textContent='Orijinal yedek: '+r.backup;}
 function button(id,title,handler){const b=document.createElement('button');b.id=id;b.textContent=title;b.onclick=async()=>{if(busy)return;busy=true;b.disabled=true;try{await handler()}catch(e){toast(e.message);document.querySelector('#desktop-result').textContent=e.message}finally{busy=false;b.disabled=id==='desktop-apply'&&!canApply}};buttons.append(b);return b}
 const result=document.createElement('p');result.id='desktop-result';result.className='muted';result.style='margin-top:12px;overflow-wrap:anywhere';buttons.after(result);
 button('desktop-find','Steam kaydını bul',async()=>{const rows=await api.list_saves();if(!rows.length)throw Error('Çevrimdışı Steam karakteri bulunamadı. Oyunda bir karakter oluşturup kaydedin.');const dialog=document.createElement('dialog');const heading=document.createElement('h2');heading.textContent='Çevrimdışı karakterini seç';dialog.append(heading);for(const row of rows){const b=document.createElement('button');b.style='display:block;margin:12px 0;width:100%;text-align:left';b.textContent=`Seviye ${row.level} · ${row.emeralds} zümrüt · ${row.items} eşya — ${row.name}`;b.onclick=async()=>{dialog.close();dialog.remove();try{await load(row.path)}catch(e){toast(e.message)}};dialog.append(b)}const close=document.createElement('button');close.textContent='Vazgeç';close.onclick=()=>{dialog.close();dialog.remove()};dialog.append(close);document.body.append(dialog);dialog.showModal()});
 button('desktop-apply','Kaydı oyuna uygula',async()=>{if(!DungeonsNative.getText())throw Error('Önce karakter kaydı açın.');result.textContent='Yedek alınıyor ve kayıt uygulanıyor…';const r=message(await api.apply_save(toB64(DungeonsNative.getBytes())));result.textContent=r.message+' Yedek: '+r.backup;toast('Kayıt oyuna uygulandı.');}).classList.add('primary');document.querySelector('#desktop-apply').disabled=true;
 button('desktop-game','Oyunu başlat',async()=>{message(await api.launch_game());toast('Steam oyunu başlatıyor. Aynı çevrimdışı karakteri yükle.');});
 document.querySelector('#native-open').onclick=()=>load(null).catch(e=>toast(e.message));
 window.DungeonsDesktop={download:async(bytes,name)=>{try{const r=message(await api.save_file(toB64(bytes),name));if(!r.cancelled)toast('Kopya kaydedildi: '+r.path)}catch(e){toast(e.message)}}};
}
window.initDungeonsDesktop=initDungeonsDesktop;
window.addEventListener('pywebviewready',initDungeonsDesktop);
initDungeonsDesktop();
const bridgeCheck=setInterval(()=>{initDungeonsDesktop();if(document.querySelector('#desktop-find'))clearInterval(bridgeCheck)},100);
})();
