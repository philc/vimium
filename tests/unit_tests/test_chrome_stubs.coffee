global.chrome ||= {}
global.chrome.storage ||= {}

global.chrome.storage.onChanged ||=
  addListener: (changes,area) ->

global.chrome.storage.sync ||=
  set: (key,value,callback) ->
  get: (keys,callback) ->
  remove: (key,callback) ->

