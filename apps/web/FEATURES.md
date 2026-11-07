# Browser feature expansion

The web preview now supports regular/private page groups, private history/persistence isolation within this preview, recently closed pages, local page finding, sharing/copying, search provider selection, content zoom, and local-data controls. It cannot create a system incognito browser window or alter cookies/permissions for external websites opened in new tabs.

Downloads support CORS-enabled HTTPS resources up to 100 MB, byte progress, cancellation, pausing, retries, server-supported Range continuation, local IndexedDB storage and export. System background downloads and authenticated external website sessions are native-only. The preview must remain open for active downloads.

Reading adds title/full-text/tag search, editing, a contents view, text export, JSON backup/restore including original files, and explicit external translation for up to 5000 selected/text characters. Translation opens Google Translate only after user action. Scanned PDF OCR and legacy .doc remain unsupported.

The integrated video layer adds playback rate, SRT/VTT tracks, Picture in Picture and AirPlay/Remote Playback buttons when browser APIs exist. Actual support is browser/device-dependent. All player actions remain in the same auto-hiding control layer; cache actions remain icon-only.

Privacy and data tools in this preview apply only to this site. Fraud warnings, TLS validation, per-site camera/microphone permissions, actual desktop-site requests, content blocking, default-browser eligibility and system integration live in the native iOS source. The settings UI explains that boundary rather than presenting ineffective toggles.

Verification: 73 Node unit tests pass. IndexedDB tests use fake-indexeddb and download tests use controlled Response/ReadableStream instances. Static assets and JavaScript syntax pass. Browser interaction, service worker installation, browser media APIs and Safari/iPhone behavior have not been tested in this environment.
