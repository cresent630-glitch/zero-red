(function(root){
  const escapeHTML=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function resolve(input){
    const value=input.trim();if(!value)return null;
    if(['zero:read','zero:video'].includes(value))return{type:value==='zero:read'?'article':'video',url:value};
    const web=s=>{try{const u=new URL(s);return ['http:','https:'].includes(u.protocol)&&u.hostname&&!u.username&&!u.password&&!/\s/.test(s)?u:null}catch{return null}};
    let url=web(value);if(url)return{type:'external',url:url.href};
    if(!/^[a-z][a-z\d+.-]*:\/\//i.test(value)&&!/[\s@]/.test(value)){url=web('https://'+value);if(url&&(url.hostname.includes('.')||url.hostname==='localhost'))return{type:'external',url:url.href}}
    return{type:'search',url:'https://www.bing.com/search?q='+encodeURIComponent(value),query:value};
  }
  function record(history,page,now=Date.now()){
    const next={...page,date:now};return [next,...(history[0]?.url===page.url?history.slice(1):history)].slice(0,1000);
  }
  function bookmark(items,page){return items.some(p=>p.url===page.url)?items:[{...page,date:Date.now()},...items]}
  function read(storage,key,fallback){try{const value=JSON.parse(storage.getItem(key));return value===null?fallback:value}catch{return fallback}}
  class BrowserTabs {
    constructor(saved) {
      this.tabs=[];this.recentlyClosed=Array.isArray(saved?.recentlyClosed)?saved.recentlyClosed.filter(t=>t&&!t.isPrivate&&Array.isArray(t.stack)).slice(0,10):[];
      if(saved && Array.isArray(saved.tabs)) {
        for(const tab of saved.tabs.slice(0,50)) {
          if(!tab || tab.isPrivate || typeof tab.id!=='string' || this.tabs.some(t=>t.id===tab.id) || !Array.isArray(tab.stack))continue;
          const stack=tab.stack.slice(-100).filter(p=>p===null || (p && ['article','video','search','external'].includes(p.type) && typeof p.url==='string' && (p.type==='article'?p.url==='zero:read':p.type==='video'?p.url==='zero:video':/^https?:$/.test((()=>{try{return new URL(p.url).protocol}catch{return ''}})()))));
          this.tabs.push({id:tab.id,stack,position:Math.max(-1,Math.min(Number.isInteger(tab.position)?tab.position:stack.length-1,stack.length-1)),draft:typeof tab.draft==='string'?tab.draft:'',isPrivate:false});
        }
      }
      this.activeId=this.tabs.some(t=>t.id===saved?.activeId)?saved.activeId:this.tabs[0]?.id;
      if(!this.tabs.length)this.create();
    }
    get active(){return this.tabs.find(t=>t.id===this.activeId)}
    get current(){return this.active.stack[this.active.position]||null}
    get canBack(){return this.active.position>0}
    get canForward(){return this.active.position<this.active.stack.length-1}
    create(isPrivate=this.active?.isPrivate||false){if(this.tabs.length>=50)return null;const tab={id:globalThis.crypto?.randomUUID?.()||Date.now().toString(36)+Math.random().toString(36).slice(2),stack:[],position:-1,draft:'',isPrivate};this.tabs.push(tab);this.activeId=tab.id;return tab}
    select(id){if(!this.tabs.some(t=>t.id===id))return false;this.activeId=id;return true}
    close(id){const index=this.tabs.findIndex(t=>t.id===id);if(index<0)return false;const wasActive=this.activeId===id,closed=this.tabs.splice(index,1)[0];if(!closed.isPrivate)this.recentlyClosed=[closed,...this.recentlyClosed.filter(t=>t.id!==id)].slice(0,10);if(!this.tabs.length)this.create(false);else if(wasActive)this.activeId=this.tabs[Math.min(index,this.tabs.length-1)].id;return true}
    reopen(id){const index=this.recentlyClosed.findIndex(t=>t.id===id);if(index<0||this.tabs.length>=50)return false;const tab=this.recentlyClosed.splice(index,1)[0];if(this.tabs.some(t=>t.id===tab.id))return false;const safe=new BrowserTabs({tabs:[tab],activeId:tab.id});if(safe.tabs[0]?.id!==tab.id)return false;Object.assign(tab,safe.tabs[0]);tab.isPrivate=false;this.tabs.push(tab);this.activeId=tab.id;return true}
    togglePrivate(){const mode=!this.active.isPrivate;const target=this.tabs.find(t=>!!t.isPrivate===mode);if(target)this.activeId=target.id;else this.create(mode)}
    endPrivate(){this.tabs=this.tabs.filter(t=>!t.isPrivate);if(!this.tabs.length)this.create(false);else if(!this.tabs.some(t=>t.id===this.activeId))this.activeId=this.tabs[0].id}
    navigate(page){const tab=this.active;tab.stack=tab.stack.slice(0,tab.position+1);tab.stack.push(page?{...page,scrollY:0}:null);if(tab.stack.length>100)tab.stack.shift();tab.position=tab.stack.length-1;tab.draft=page?.query||page?.url||''}
    move(offset){const tab=this.active,next=tab.position+offset;if(next<0||next>=tab.stack.length)return false;tab.position=next;tab.draft=this.current?.query||this.current?.url||'';return true}
    rememberScroll(y){if(this.current)this.current.scrollY=Math.max(0,Number(y)||0)}
    snapshot(){const regular=this.tabs.filter(t=>!t.isPrivate);return {tabs:regular,activeId:regular.some(t=>t.id===this.activeId)?this.activeId:regular[0]?.id,recentlyClosed:this.recentlyClosed.filter(t=>!t.isPrivate)}}
  }
  function videoTarget(video,base){
    if(!video)throw Error('no-video');
    if(video.cachedId)return {cachedId:video.cachedId,title:video.title||'Video'};
    const source=video.currentSrc||video.src;
    if(!source)throw Error('no-video');
    let url;try{url=new URL(source,base)}catch{throw Error('unsupported-video')}
    if(!['http:','https:'].includes(url.protocol)||url.username||url.password||/\.(m3u8|mpd)$/i.test(url.pathname))throw Error('unsupported-video');
    return {source:url.href,title:video.title||decodeURIComponent(url.pathname.split('/').pop()||'Video')};
  }
  function searchURL(query,provider='bing'){const base={bing:'https://www.bing.com/search',google:'https://www.google.com/search',duckduckgo:'https://duckduckgo.com/',baidu:'https://www.baidu.com/s'};const url=new URL(base[provider]||base.bing);url.searchParams.set(provider==='baidu'?'wd':'q',query);return url.href}
  function parseSubtitles(input){const seconds=value=>{const parts=value.trim().replace(',','.').split(':').map(Number);if(parts.some(n=>!Number.isFinite(n))||parts.length<2||parts.length>3)return NaN;return parts.reduce((a,b)=>a*60+b,0)};return input.replace(/\r\n?/g,'\n').split(/\n\s*\n/).flatMap(block=>{const lines=block.split('\n'),index=lines.findIndex(line=>line.includes('-->'));if(index<0)return [];const times=lines[index].split('-->'),start=seconds(times[0]),end=seconds(times[1].trim().split(/\s/)[0]);if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start)return [];return [{start,end,text:lines.slice(index+1).join('\n').replace(/<[^>]*>/g,'')}]})}
  function downloadResponse(status,headers,received,previousETag){
    if(status===200)return {reset:true,expected:Number(headers.get('content-length'))||0};
    if(status!==206)throw Error('HTTP '+status);
    const range=headers.get('content-range')?.match(/^bytes (\d+)-(\d+)\/(\d+)$/);
    if(!range||Number(range[1])!==received||Number(range[2])<Number(range[1])||Number(range[2])>=Number(range[3]))throw Error('Invalid resume range');
    if(previousETag&&headers.get('etag')&&previousETag!==headers.get('etag'))throw Error('File changed; restart download');
    return {reset:false,expected:Number(range[3])};
  }
  const api={escapeHTML,resolve,record,bookmark,read,BrowserTabs,videoTarget,searchURL,parseSubtitles,downloadResponse};root.ZeroCore=api;if(typeof module!=='undefined')module.exports=api;
})(globalThis);
