root = exports ? window

root.isVimiumBackgroundPage =
  if root.isVimiumExtensionPage? and root.isVimiumExtensionPage
    # This is an extension page other than the background page.  "isVimiumExtensionPage" is set by
    # "../pages/content_script_loader.coffee".
    false
  else
    # This is the background page.  This sets both "isVimiumExtensionPage" and "isVimiumBackgroundPage".
    root.isVimiumExtensionPage = true
