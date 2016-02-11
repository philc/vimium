root = exports ? window

# This script is only loaded by non-background extension pages, and is always loaded first.
# See "../pages/content_script_loader.coffee".

root.isVimiumExtensionPage = true
