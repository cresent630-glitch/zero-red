import Foundation

enum PageScripts {
    static let videoPlaybackBridge = #"""
    (() => {
        let gesture = -Infinity;
        let lastSource = '', lastRequest = -Infinity;
        window.__zeroRedReleaseVideo = (source, position) => {
            lastSource = ''; lastRequest = -Infinity;
            document.querySelectorAll('video').forEach(video => {
                if ((video.currentSrc || video.src) === source) {
                    video.pause();
                    if (Number.isFinite(position)) { try { video.currentTime = Number.isFinite(video.duration) && position >= video.duration - 0.15 ? 0 : position; } catch (_) {} }
                }
            });
        };
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
            const position = video.ended || (Number.isFinite(video.duration) && video.currentTime >= video.duration - 0.15) ? 0 : (Number.isFinite(video.currentTime) ? video.currentTime : 0);
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
    await new Promise(resolve => {
        let quiet;
        const observer = new MutationObserver(() => { clearTimeout(quiet); quiet = setTimeout(finish, 400); });
        const finish = () => { observer.disconnect(); clearTimeout(quiet); clearTimeout(maximum); resolve(); };
        const maximum = setTimeout(finish, 1800);
        observer.observe(document, {subtree:true, childList:true, characterData:true});
        quiet = setTimeout(finish, 400);
    });
    const skip = new Set(['SCRIPT','STYLE','NOSCRIPT','TEMPLATE','SVG','CANVAS','INPUT']);
    const blocks = new Set(['P','DIV','SECTION','ARTICLE','MAIN','HEADER','FOOTER','NAV','ASIDE','H1','H2','H3','H4','H5','H6','LI','UL','OL','BLOCKQUOTE','PRE','TR','FIGCAPTION']);
    let length = 0;
    function text(node) {
        if (!node) return '';
        if (length >= 1000000) return '';
        if (node.nodeType === 3) { length += node.nodeValue.length; return node.nodeValue; }
        if (node.nodeType !== 1 && node.nodeType !== 11) return '';
        if (node.nodeType === 1) {
            if (skip.has(node.tagName) || node.hidden || node.getAttribute('aria-hidden') === 'true') return '';
            const style = node.ownerDocument.defaultView.getComputedStyle(node);
            if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse') return '';
            if (node.tagName === 'BR') return '\n';
            if (node.tagName === 'IFRAME') { try { return '\n\n' + text(node.contentDocument.body) + '\n\n'; } catch (_) { return ''; } }
            if (node.tagName === 'DETAILS' && !node.open) return text(node.querySelector('summary'));
        }
        const children = node.shadowRoot || node;
        const result = Array.from(children.childNodes, text).join('');
        if (/^H[1-6]$/.test(node.tagName || '')) return '\n\n' + '#'.repeat(Number(node.tagName[1])) + ' ' + result + '\n\n';
        return blocks.has(node.tagName) ? '\n\n' + result + '\n\n' : result;
    }
    return {title:document.title || location.hostname, text:text(document.body).replace(/\n[ \t]+/g,'\n').replace(/\n{3,}/g,'\n\n').trim().slice(0,1000000), source:location.href};
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
