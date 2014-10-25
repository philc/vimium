
# TODO(smblott) Delay attaching VIM until the text area is activated.
document.addEventListener "DOMContentLoaded", ->
  for textarea in document.getElementsByTagName "textarea"
    vim = new VIM()
    console.log textarea
    vim.attach_to textarea

