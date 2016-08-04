root = exports ? window

# This script is only loaded on the background page.
# On extension pages other than the background page, these context variables are set in
# "../pages/content_script_loader.coffee".

root.isVimiumBackgroundPage = root.isVimiumExtensionPage = true
