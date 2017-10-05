window.injectContentScripts = (tabId) ->
  chrome.tabs.get tabId, (tab) ->
    chrome.runtime.getManifest().content_scripts.map? (contentScripts) ->
      {matches, css, js, run_at, all_frames, match_about_blank} = contentScripts
      # NOTE(mrmr1993): This doesn't do matching properly at all.
      if 0 <= matches?.indexOf "<all-urls>"
        css?.map (style) ->
          chrome.tabs.insertCSS tabId,
            file: chrome.runtime.getURL style
            runAt: run_at
            allFrames: all_frames
            matchAboutBlank: match_about_blank
        js?.map (script) ->
          chrome.tabs.executeScript tabId,
            file: chrome.runtime.getURL script
            runAt: run_at
            allFrames: all_frames
            matchAboutBlank: match_about_blank

base_location = location.search.split("test_base_location=")[1].split("&")[0]

chrome.tabs.create {url: "#{base_location}/link_hints.html", active: true},
  (tab) ->
    #console.log tab
    #injectContentScripts tab.id
    return
