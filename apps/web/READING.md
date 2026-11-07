# Reading preview

Reading and Videos are sibling library tabs. Reading supports pasted text and local TXT, Markdown, HTML, PDF and DOCX files up to 20 MB; extracted text is limited to 1 million characters, PDFs to 500 pages. UTF-8, UTF-16 and GB18030 fallback text decoding is included.

Files and extracted text are saved in IndexedDB on the current device. A v1 → v2 migration adds the documents store while preserving videos. Reading progress is saved after scrolling and on close. Browser storage clearing can remove saved data.

The reader hides browser navigation, supports 14–28 px text size, three line spacings, serif/sans fonts, light/dark themes, and a focus view. For PDF scans without a text layer, the original is saved and may be opened using the browser PDF viewer. OCR, password-protected PDFs and legacy .doc are not supported. DOCX tables/formatting are simplified to text.

Article text can be extracted from the built-in reading demo. Remote HTML extraction requires the destination to allow CORS; otherwise paste the text or import a document. No proxy or server-side scraping is used. PDF.js 4.10.38 and Mammoth 1.9.1 are bundled locally, with licenses in dist/vendor.

The service worker caches the preview shell and bundled parsers for offline reopening after a successful online installation. It uses network-first requests for the static app assets to avoid stale online updates. Service worker, file-picker, PDF worker and visual interactions have not been tested in an actual browser in this environment.

Tests: `npm install` then `npm test` (fake-indexeddb is a test-only dependency). The expanded preview passes 73 tests across navigation, privacy, reading, storage, downloads and player controls; see FEATURES.md. The tests do not replace Safari/iPhone or native iOS validation.
