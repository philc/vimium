
document.addEventListener "DOMContentLoaded", ->
  for ele in document.getElementsByTagName "textarea"
    do (ele) ->
      ele.addEventListener "focus", ->
        if not ele.__vimium_vim_attached
          vim = ele.__vimium_vim_attached = new VIM()
          vim.attach_to ele

