/* Embedded inside native.js: saved Intensity values stay separate from display units. */
const effectViews=new Map();
const bonusEffects=new Set(['Protection','Sharpness','RapidStrike','SpeedBoost','Cooldown','Power','Constitution','Finesse','FireFocus','ProjectileProtection','Vestige','LightningFocus','SoulFocus','PoisonFocus','CriticalEdge','MasterStrike','MasterMarksman','Reconstruction','Supercharge','ElementalProtection','Opportunist','SwiftSneak','SweepingEdge','PotionCooldown','FrostFocus','PointBlank','Sniper','SoulGatherMultiply','Vivify','Resilience','Saboteur','HealingFocus','ShadowWalk','Duelist','BeastBoss','Knockback','Friendship','FriendsForever','Committed','Vanguard']);
const chanceEffects=new Set(['CriticalHit','Sidestep','Precision','EagleEye','Reeling','Deflect','Looting','Opulence','Gambler','MultiShot','Chains','EmeraldsIncrease','Lucky','ArrowBurst']);
function valueRule(path){
 const tag=val([...path.slice(0,-1),'TypeTag']),suffix=tag?.split('.').at(-1);
 if(tag?.startsWith('SW.Effect.')&&bonusEffects.has(suffix))return 'bonus';
 if(tag?.startsWith('SW.Effect.')&&chanceEffects.has(suffix))return 'chance';
 if(['SW.Effect.SoulMax','SW.Effect.AmmoCapacity','SW.Enchantment.FireAspect'].includes(tag))return 'ratio';
 return 'unknown';
}
function displayAmount(value,unit,rule){return unit==='percent'?value*100:unit==='multiplier'&&rule==='bonus'?1+value:value}
function readableAmount(value){return String(Number(value.toPrecision(15)))}
function storedAmount(el,text){
 const value=Number(numeric(text)),unit=el.dataset.effectUnit,rule=valueRule(JSON.parse(el.dataset.nativePath));
 let stored=unit==='percent'?value/100:unit==='multiplier'&&rule==='bonus'?value-1:value;
 stored=Number(stored.toPrecision(15));
 if(!Number.isFinite(stored)||Math.abs(stored)>1000000)throw Error('Etki değeri sonlu ve -1.000.000 ile 1.000.000 arasında olmalı.');
 if(rule==='chance'&&(stored<0||stored>1))throw Error('Olasılık %0 ile %100 arasında olmalı.');
 if(rule==='bonus'&&stored< -1)throw Error('Toplam çarpan negatif olamaz.');
 return String(stored);
}
function effectValueControl(x){
 const p=x.path,rule=valueRule(p),value=Number(raw(x));
 if(!Number.isFinite(value)||Math.abs(value)>1000000)return null;
 const unit=effectViews.get(key(p))||(rule==='unknown'?'raw':'percent');
 const modes=[['raw','Sabit / kayıt değeri'],['percent','Yüzde (%)']];
 if(rule!=='chance')modes.push(['multiplier',rule==='bonus'?'Toplam çarpan (×)':'Çarpan gösterimi (×)']);
 const help=rule==='bonus'?'Bonus: %100 = toplam ×2. Negatif yüzde, azaltma anlamına gelir.':rule==='chance'?'Olasılık: %100 her denemede gerçekleşme demektir.':rule==='ratio'?'Oran: %100 = ×1; %200 = ×2.':'Birim bilinmiyor. Yüzde/çarpan seçimi yalnız sayının gösterimini değiştirir.';
 return `<div class="native-field effect-value"><label>Etki değeri</label><select data-effect-view="${h(key(p))}" aria-label="Değer gösterimi">${modes.map(([mode,label])=>`<option value="${mode}" ${mode===unit?'selected':''}>${h(label)}</option>`).join('')}</select><input data-native-path="${h(key(p))}" data-effect-unit="${unit}" value="${h(unit==='raw'?raw(x):readableAmount(displayAmount(value,unit,rule)))}" inputmode="decimal" aria-label="Etki değeri"><p class="muted effect-help">${h(help)}</p><small>${h(p.join('.'))}</small></div>`;
}
function effectFields(i){
 const list=n([...i,'ItemData','Effects']);if(!list?.children.length)return '<p class="muted">Bu eşyada kayıtlı büyü/etki yok.</p>';
 return list.children.map(batch=>{
  const effects=n([...batch.path,'EffectsInThisBatch']),enchant=val([...batch.path,'TypeTag'])==='SW.Item.Effect.Enchantment';
  if(!effects)return `<div class="row">${leaves(batch).map(x=>control(x)).join('')}</div>`;
  return effects.children.map(effect=>{
   const tag=val([...effect.path,'TypeTag']),template=val([...effect.path,'GeneratorData','GeneratorParentTemplate']),entry=iconEntry(template)||iconEntry(tag);
   const primary=leaves(effect).filter(x=>['Intensity','GeneratorParentTemplate'].includes(x.path.at(-1)));
   const other=leaves(effect).filter(x=>!primary.includes(x)&&x.path.at(-1)!=='TypeTag');
   return `<section class="effect-card"><div class="effect-portrait">${picture(entry?.id||template||tag,true)}<div><span class="effect-kind">${enchant?'Büyü':'Ekipman etkisi'}</span><strong>${h(entry?.name||tag||'Etki')}</strong><small class="native-code">${h(template||tag||'')}</small></div><div class="effect-actions">${n([...effect.path,'Intensity'])&&n([...effect.path,'GeneratorData','GeneratorParentTemplate'])?(enchant?`<button data-enchantment-edit="${h(key(effect.path))}">Büyüyü değiştir</button>`:`<button data-effect-pick="${h(key(effect.path))}">Etkiyi değiştir</button>`):''}<button class="danger" data-effect-remove="${h(key(effect.path))}">Kaldır</button></div></div><div class="row">${primary.map(x=>control(x)).join('')}</div>${other.length?`<details><summary>Diğer etki ayarları</summary><div class="row">${other.map(x=>control(x)).join('')}</div></details>`:''}</section>`;
  }).join('');
 }).join('');
}
function showEffectPicker(path){
 try{validatePending()}catch(err){toast(err.message);return}
 const rows=icons.entries.filter(e=>e.kind==='effect'&&e.nativeFields?.effect&&typeof e.nativeFields.value==='number');
 const choices=rows.filter((e,index)=>rows.findIndex(r=>r.nativeFields.effect===e.nativeFields.effect)===index);
 let selected=null;const dialog=document.createElement('dialog');dialog.className='item-picker';
 dialog.innerHTML='<h2>'+h(path?'Ekipman etkisini seç':'Özellik ekle')+'</h2><p class="muted">'+h(path?'Mevcut etki değiştirilir. Her eşya / etki birleşimi oyunda doğrulanmış değildir.':'Yeni özellik eklenir. Mevcut büyüler ve özellikler korunur. Her birleşimi oyunda kontrol et.')+'</p><label>Etki ara</label><input id="effect-search"><div class="picker-list"></div><label>Kademe</label><select id="effect-tier" disabled></select><div class="actions"><button id="effect-apply" class="primary" disabled>Etkiyi uygula</button><button id="effect-cancel">Vazgeç</button></div>';
 function redraw(){const search=dialog.querySelector('#effect-search').value.toLocaleLowerCase('tr');dialog.querySelector('.picker-list').innerHTML=choices.filter(e=>e.name.toLocaleLowerCase('tr').includes(search)).map(e=>`<button class="picker-choice" data-effect-choice="${h(e.nativeFields.effect)}">${picture(e.id,true)}<span>${h(e.name)}</span></button>`).join('')}
 dialog.querySelector('#effect-search').oninput=redraw;
 dialog.querySelector('#effect-cancel').onclick=()=>{dialog.close();dialog.remove()};
 dialog.addEventListener('click',e=>{const b=e.target.closest('[data-effect-choice]');if(!b)return;selected=b.dataset.effectChoice;const tier=dialog.querySelector('#effect-tier');tier.innerHTML=rows.filter(r=>r.nativeFields.effect===selected).map(r=>`<option value="${h(r.tag)}">${h(tierName(r.nativeFields.tier))}</option>`).join('');tier.disabled=false;dialog.querySelector('#effect-apply').disabled=false;});
 dialog.querySelector('#effect-apply').onclick=()=>{try{
  validatePending();const entry=rows.find(r=>r.tag===dialog.querySelector('#effect-tier').value);if(!entry||(path&&!n(path)))throw Error('Listeden geçerli bir seçenek seç.');
  if(!path){appendSavedEffect(n(IP).children[itemIndex].path,'SW.Item.Effect.Rerollable',{TypeTag:entry.nativeFields.effect,Intensity:entry.nativeFields.value,Quality:0,EnchantmentPointsInvested:0,GeneratorData:{GeneratorParentTemplate:entry.tag,Locked:false}});dialog.close();dialog.remove();return;}
  effectViews.delete(key([...path,'Intensity']));
  patch([[[...path,'TypeTag'],JSON.stringify(entry.nativeFields.effect)],[[...path,'Intensity'],String(entry.nativeFields.value)],[[...path,'GeneratorData','GeneratorParentTemplate'],JSON.stringify(entry.tag)]]);
  dialog.close();dialog.remove();
 }catch(err){toast(err.message)}};
 dialog.addEventListener('close',()=>dialog.remove());document.body.append(dialog);redraw();dialog.showModal();
}

function appendSavedEffect(itemPath,batchTag,effect){
 const list=n([...itemPath,'ItemData','Effects']);if(list?.kind!=='array')throw Error('Bu eşyanın etki listesi eksik.');
 const batch=list.children.find(b=>val([...b.path,'TypeTag'])===batchTag&&n([...b.path,'EffectsInThisBatch'])?.kind==='array');
 const target=batch?n([...batch.path,'EffectsInThisBatch']):list;
 const added=batch?effect:{TypeTag:batchTag,EffectsInThisBatch:[effect]};
 patch([[target.path,raw(target).slice(0,-1)+(target.children.length?',':'')+JSON.stringify(added)+']']]);
}
function removeArrayNode(path){
 const node=n(path),array=n(path.slice(0,-1));if(!node||array?.kind!=='array')throw Error('Etki bulunamadı.');
 const index=path.at(-1);let start=node.start,end=node.end;
 if(array.children.length>1){if(index<array.children.length-1)end=array.children[index+1].start;else start=array.children[index-1].end;}
 adopt(save.text.slice(0,start)+save.text.slice(end));
}
function removeSavedEffect(path){
 const array=n(path.slice(0,-1));if(array?.kind!=='array'||path.at(-2)!=='EffectsInThisBatch')throw Error('Etki bulunamadı.');
 effectViews.clear();removeArrayNode(array.children.length===1?path.slice(0,-2):path);
}
