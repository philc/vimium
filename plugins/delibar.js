function runDelibar() {
    document.location='Delibar://bpost'+'&!p!&'+document.location.href+'&!p!&'+encodeURIComponent(document.title)+'&!p!&'+encodeURIComponent(document.getSelection());
}
