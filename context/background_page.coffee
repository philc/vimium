root = exports ? window

# This script is loaded by all extension pages, including the background page. If "extension_page.coffee" is
# loaded too, then that script is loaded first.  Therefore, we can tell the difference between the background
# page and other extension pages.

root.isVimiumBackgroundPage =
  if root.isVimiumExtensionPage? and root.isVimiumExtensionPage
    false
  else
    # This sets both isVimiumExtensionPage and isVimiumBackgroundPage.
    root.isVimiumExtensionPage = true
