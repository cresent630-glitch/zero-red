import Foundation

enum PageScripts {
    static let videoPlaybackBridge = #"""
    (() => {
        let gesture = -Infinity;
        let lastSource = '', lastRequest = -Infinity;
        for (const name of ['pointerdown', 'touchstart', 'keydown']) {
            document.addEventListener(name, event => { if (event.isTrusted) gesture = Date.now(); }, true);
        }
        function prepare(video) {
            if (!(video instanceof HTMLVideoElement)) return;
            if (!video.playsInline) video.playsInline = true;
            if (!video.hasAttribute('webkit-playsinline')) video.setAttribute('webkit-playsinline', '');
        }
        function route(video) {
            if (!(video instanceof HTMLVideoElement)) return false;
            const source = video.currentSrc || video.src;
            if (!/^https?:/i.test(source)) return false;
            const now = Date.now();
            if (source === lastSource && now - lastRequest < 1000) return true;
            lastSource = source; lastRequest = now;
            const position = Number.isFinite(video.currentTime) ? video.currentTime : 0;
            video.pause();
            window.webkit.messageHandlers.zeroRed.postMessage({type:'videoPlayback', source, position});
            return true;
        }
        function scan(root) {
            if (root instanceof HTMLVideoElement) prepare(root);
            if (root.querySelectorAll) root.querySelectorAll('video').forEach(prepare);
        }
        // A site's app-launch overlay can cover its actual video element.
        // A direct tap inside that video should use the same native controls.
        for (const name of ['click', 'touchend']) {
            document.addEventListener(name, event => {
                if (!event.isTrusted) return;
                const point = event.changedTouches ? event.changedTouches[0] : event;
                for (const video of document.querySelectorAll('video')) {
                    const rect = video.getBoundingClientRect();
                    if (rect.width > 0 && rect.height > 0 && point.clientX >= rect.left && point.clientX <= rect.right && point.clientY >= rect.top && point.clientY <= rect.bottom && route(video)) {
                        event.preventDefault(); event.stopImmediatePropagation(); return;
                    }
                }
            }, {capture:true, passive:false});
        }
        new MutationObserver(records => {
            for (const record of records) {
                if (record.type === 'attributes') prepare(record.target);
                else record.addedNodes.forEach(scan);
            }
        }).observe(document, {subtree:true, childList:true, attributes:true, attributeFilter:['playsinline','webkit-playsinline']});
        document.addEventListener('play', event => {
            if (Date.now() - gesture < 2000) route(event.target);
        }, true);
        for (const name of ['webkitEnterFullscreen', 'webkitEnterFullScreen']) {
            const original = HTMLVideoElement.prototype[name];
            if (typeof original !== 'function') continue;
            HTMLVideoElement.prototype[name] = function(...args) {
                if (Date.now() - gesture < 2000 && route(this)) return;
                return original.apply(this, args);
            };
        }
        for (const name of ['requestFullscreen', 'webkitRequestFullscreen', 'webkitRequestFullScreen']) {
            const original = Element.prototype[name];
            if (typeof original !== 'function') continue;
            Element.prototype[name] = function(...args) {
                const video = this instanceof HTMLVideoElement ? this : this.querySelector('video');
                if (Date.now() - gesture < 2000 && route(video)) return Promise.resolve();
                return original.apply(this, args);
            };
        }
        scan(document);
    })();
    """#
    static let reader = #"""
    (()=>{const root=(document.querySelector('article')||document.querySelector('main')||document.body).cloneNode(true);root.querySelectorAll('script,style,nav,header,footer,aside,form,button,iframe,svg,noscript,[hidden],[aria-hidden="true"]').forEach(n=>n.remove());const block=new Set(['P','DIV','SECTION','ARTICLE','MAIN','H1','H2','H3','H4','LI','UL','OL','BLOCKQUOTE','PRE','TR']);function text(n){if(n.nodeType===3)return n.nodeValue;if(n.nodeType!==1)return '';if(n.tagName==='BR')return '\n';const s=Array.from(n.childNodes,text).join('');return block.has(n.tagName)?'\n\n'+s+'\n\n':s}return {title:document.title||location.hostname,text:text(root).replace(/\n{3,}/g,'\n\n').trim().slice(0,1000000),source:location.href}})()
    """#
    static let bridge = #"""
    (()=>{let last=0;addEventListener('scroll',()=>{if(Date.now()-last<600)return;last=Date.now();window.webkit.messageHandlers.zeroRed.postMessage({type:'scroll',y:scrollY})},{passive:true});})()
    """#
    static let videoLinks = #"""
    Array.from(new Set(Array.from(document.querySelectorAll('video,video source')).map(v=>v.currentSrc||v.src).filter(s=>/^https?:/.test(s))))
    """#
    static let fullscreenVideo = #"""
        const videos = Array.from(document.querySelectorAll('video'));
        const video = videos.find(v => !v.paused && !v.ended) || videos.sort((a,b) => b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight)[0];
        if (!video) return 'missing';
        video.controls = true;
        let timeout;
        try {
            await Promise.race([
                video.play(),
                new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('Playback timed out')), 10000); })
            ]);
            if (!video.webkitDisplayingFullscreen && !document.fullscreenElement) {
                if (typeof video.webkitEnterFullscreen === 'function') video.webkitEnterFullscreen();
                else if (video.requestFullscreen) await video.requestFullscreen();
                else return 'unsupported';
            }
            if (video.webkitDisplayingFullscreen || document.fullscreenElement) return 'opened';
            return await new Promise(resolve => {
                let timer;
                const finish = () => {
                    clearTimeout(timer);
                    video.removeEventListener('webkitbeginfullscreen', finish);
                    document.removeEventListener('fullscreenchange', finish);
                    resolve(video.webkitDisplayingFullscreen || document.fullscreenElement ? 'opened' : 'unsupported');
                };
                video.addEventListener('webkitbeginfullscreen', finish, {once:true});
                document.addEventListener('fullscreenchange', finish, {once:true});
                timer = setTimeout(finish, 2500);
            });
        } catch (_) { return 'unsupported'; }
        finally { clearTimeout(timeout); }
    """#
}
