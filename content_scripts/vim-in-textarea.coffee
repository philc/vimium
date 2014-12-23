
# Activation key is Control-Alt-V while within a textarea.
isVimActivationEvent = (event) ->
  event.ctrlKey and event.altKey and not event.metaKey and event.keyCode == 86 # "V"

document.addEventListener "DOMContentLoaded", ->
  for ele in document.getElementsByTagName "textarea"
    do (ele) ->
      # TODO(smblott) Is there a better way to record that vim is activated?
      ele.addEventListener "keydown", (event) ->
        if isVimActivationEvent event
          if not ele.__vimium_vim_attached
            # Activate vim mode.
            vim = ele.__vimium_vim_attached = new VIM()
            vim.attach_to ele

            HUD.showForDuration "Vim-mode activated", 1500
            ele.addEventListener "focus", ->
              HUD.showForDuration "Vim-mode active (#{vim.m_mode})", 1000

          else
            # If vim mode is already activated, then hitting the activation keystroke again
            # pulls up the HUD to show the current vim mode.
            HUD.showForDuration "Vim-mode: #{ele.__vimium_vim_attached.m_mode}", 1000

          event.preventDefault()
          event.stopPropagation()

