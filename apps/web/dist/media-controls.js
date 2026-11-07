(function(root){
  class MediaVisibility {
    constructor(change,{delay=2400,schedule=setTimeout,cancel=clearTimeout}={}){this.change=change;this.delay=delay;this.schedule=schedule;this.cancel=cancel;this.playing=false;this.visible=true;this.pinned=false;this.timer=null;this.disposed=false}
    clear(){if(this.timer!==null)this.cancel(this.timer);this.timer=null}
    reveal(){if(this.disposed)return;this.clear();this.visible=true;this.change(true);if(this.playing&&!this.pinned)this.timer=this.schedule(()=>{this.timer=null;if(!this.disposed&&this.playing&&!this.pinned){this.visible=false;this.change(false)}},this.delay)}
    setPlaying(value){this.playing=value;this.reveal()}
    pin(value){this.pinned=value;this.reveal()}
    toggle(){if(!this.playing||this.pinned||!this.visible){this.reveal();return}this.clear();this.visible=false;this.change(false)}
    dispose(){this.clear();this.disposed=true}
  }
  const instances=new WeakMap();
  const symbols={play:'<path d="m9 5 11 7-11 7z"/>',pause:'<path d="M8 5v14M16 5v14"/>',volume:'<path d="M4 9h4l5-4v14l-5-4H4zm13-1a6 6 0 0 1 0 8"/>',muted:'<path d="M4 9h4l5-4v14l-5-4H4zm13 1 5 5m0-5-5 5"/>',expand:'<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/>'};
  const svg=name=>`<svg viewBox="0 0 24 24" aria-hidden="true">${symbols[name]}</svg>`;
  function bind(frame,{translate=(a,b)=>b,expand}={}){
    if(!frame||instances.has(frame))return instances.get(frame);
    const video=frame.querySelector('video'),chrome=frame.querySelector('.media-chrome');if(!video||!chrome)return;
    const play=chrome.querySelector('[data-media="play"]'),mute=chrome.querySelector('[data-media="mute"]'),seek=chrome.querySelector('[data-media="seek"]'),time=chrome.querySelector('.media-time'),fullscreen=chrome.querySelector('[data-media="expand"]');
    let captionURL=null;let scrubbing=false,keyboardFocus=true;const listeners=[];
    const on=(target,event,handler,options)=>{target.addEventListener(event,handler,options);listeners.push(()=>target.removeEventListener(event,handler,options))};
    const visibility=new MediaVisibility(visible=>{frame.classList.toggle('chrome-hidden',!visible);chrome.inert=!visible;chrome.setAttribute('aria-hidden',String(!visible));if(video.id==='fullPlayer')frame.closest('.player-overlay')?.classList.toggle('chrome-hidden',!visible)});
    const stamp=value=>{value=Number.isFinite(value)?Math.max(0,Math.floor(value)):0;return `${Math.floor(value/60)}:${String(value%60).padStart(2,'0')}`};
    function update(){const paused=video.paused||video.ended;play.innerHTML=svg(paused?'play':'pause');play.setAttribute('aria-label',translate(paused?'播放':'暂停',paused?'Play':'Pause'));mute.innerHTML=svg(video.muted?'muted':'volume');mute.setAttribute('aria-label',translate(video.muted?'取消静音':'静音',video.muted?'Unmute':'Mute'));time.textContent=stamp(video.currentTime)+' / '+stamp(video.duration);const duration=Number.isFinite(video.duration)?video.duration:0;seek.disabled=!duration;if(!scrubbing)seek.value=duration?String(video.currentTime/duration*1000):'0';seek.setAttribute('aria-valuetext',stamp(video.currentTime)+' / '+stamp(duration))}
    function togglePlay(){if(video.paused||video.ended)video.play().catch(()=>visibility.reveal());else video.pause()}
    on(play,'click',togglePlay);on(mute,'click',()=>{video.muted=!video.muted;update()});
    on(fullscreen,'click',()=>{visibility.reveal();if(expand)expand();else if(document.fullscreenElement)document.exitFullscreen?.();else frame.requestFullscreen?.().catch(()=>{})});
    if(!expand&&!frame.requestFullscreen)fullscreen.hidden=true;
    const speed=chrome.querySelector('[data-media="rate"]'),pip=chrome.querySelector('[data-media="pip"]'),airplay=chrome.querySelector('[data-media="airplay"]'),captions=chrome.querySelector('[data-media="captions"]'),settings=chrome.querySelector('.media-settings');
    if(speed)on(speed,'change',()=>{video.playbackRate=Number(speed.value);visibility.reveal()});
    if(pip){pip.hidden=!(video.requestPictureInPicture||video.webkitSetPresentationMode);on(pip,'click',async()=>{try{if(document.pictureInPictureElement)await document.exitPictureInPicture();else if(video.requestPictureInPicture)await video.requestPictureInPicture();else video.webkitSetPresentationMode('picture-in-picture')}catch{root.toast?.(translate('当前浏览器或视频不支持画中画。','Picture in Picture is unavailable.'))}})}
    if(airplay){airplay.hidden=!(video.webkitShowPlaybackTargetPicker||video.remote?.prompt);on(airplay,'click',async()=>{try{if(video.webkitShowPlaybackTargetPicker)video.webkitShowPlaybackTargetPicker();else await video.remote.prompt()}catch{root.toast?.(translate('未连接到可用的播放设备。','No playback device is available.'))}})}
    if(settings)on(settings,'toggle',()=>visibility.pin(settings.open||scrubbing));
    if(captions)on(captions,'change',async()=>{try{const file=captions.files[0];if(!file)return;if(file.size>2*1024*1024)throw Error(translate('字幕文件过大。','Caption file is too large.'));const cues=root.ZeroCore.parseSubtitles(await file.text());if(!cues.length)throw Error(translate('未识别到有效字幕。','No valid captions found.'));if(captionURL)URL.revokeObjectURL(captionURL);video.querySelectorAll('track[data-zero-caption]').forEach(track=>track.remove());const stamp=n=>{const h=Math.floor(n/3600),m=Math.floor(n%3600/60),s=Math.floor(n%60),ms=Math.round((n-Math.floor(n))*1000);return [h,m,s].map(x=>String(x).padStart(2,'0')).join(':')+'.'+String(ms).padStart(3,'0')};const vtt='WEBVTT\n\n'+cues.map(c=>stamp(c.start)+' --> '+stamp(c.end)+'\n'+c.text+'\n').join('\n');captionURL=URL.createObjectURL(new Blob([vtt],{type:'text/vtt'}));const track=document.createElement('track');track.dataset.zeroCaption='true';track.kind='subtitles';track.label=file.name;track.srclang='und';track.src=captionURL;track.default=true;track.onload=()=>track.track.mode='showing';video.append(track);track.track.mode='showing';root.toast?.(translate('字幕已导入。','Captions imported.'))}catch(error){root.toast?.(error.message)}});
    on(seek,'pointerdown',()=>{scrubbing=true;visibility.pin(true)});on(window,'pointerup',()=>{if(scrubbing){scrubbing=false;visibility.pin(!!settings?.open||(keyboardFocus&&chrome.contains(document.activeElement)));update()}});
    on(seek,'input',()=>{if(Number.isFinite(video.duration)&&video.duration>0)video.currentTime=Number(seek.value)/1000*video.duration;update();visibility.reveal()});
    on(video,'play',()=>{update();visibility.setPlaying(true)});on(video,'pause',()=>{update();visibility.setPlaying(false)});on(video,'ended',()=>{update();visibility.setPlaying(false)});on(video,'error',()=>visibility.setPlaying(false));
    for(const event of ['timeupdate','loadedmetadata','durationchange','volumechange','emptied'])on(video,event,update);
    on(frame,'pointermove',event=>{if(event.pointerType==='mouse')visibility.reveal()});on(frame,'click',event=>{if(!chrome.contains(event.target))visibility.toggle()});
    on(chrome,'pointerenter',event=>{if(event.pointerType==='mouse')visibility.pin(true)});on(chrome,'pointerleave',event=>{if(event.pointerType==='mouse')visibility.pin(!!settings?.open||(keyboardFocus&&chrome.contains(document.activeElement)))});
    on(frame,'pointerdown',()=>{keyboardFocus=false},true);on(frame,'focusin',()=>visibility.pin(!!settings?.open||keyboardFocus));on(frame,'focusout',()=>{queueMicrotask(()=>{if(frame.isConnected)visibility.pin(!!settings?.open||scrubbing||(keyboardFocus&&chrome.contains(document.activeElement)))})});
    on(frame,'keydown',event=>{keyboardFocus=true;visibility.reveal();if(event.target!==frame&&event.target!==video)return;if(event.key===' '||event.key==='k'){event.preventDefault();togglePlay()}else if(event.key==='ArrowRight'||event.key==='ArrowLeft'){event.preventDefault();video.currentTime=Math.max(0,Math.min(video.duration||0,video.currentTime+(event.key==='ArrowRight'?5:-5)));visibility.reveal()}else visibility.reveal()});
    frame.tabIndex=0;video.controls=false;frame.classList.add('custom-media');update();visibility.setPlaying(!video.paused&&!video.ended);
    const controller={reveal:()=>visibility.reveal(),dispose:()=>{visibility.dispose();if(captionURL)URL.revokeObjectURL(captionURL);listeners.forEach(remove=>remove());instances.delete(frame)}};instances.set(frame,controller);return controller;
  }
  function dispose(frame){instances.get(frame)?.dispose()}
  const api={MediaVisibility,bind,dispose};root.ZeroMedia=api;if(typeof module!=='undefined')module.exports=api;
})(globalThis);
