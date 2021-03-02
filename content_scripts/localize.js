window.addEventListener('load', () => {
    document.querySelectorAll('[data-locale_text]').forEach(elem => {
        elem.innerText = chrome.i18n.getMessage(elem.dataset.locale_text)
    });
    document.querySelectorAll('[data-locale_placeholder]').forEach(elem => {
        elem.placeholder = chrome.i18n.getMessage(elem.dataset.locale_placeholder)
    });
});