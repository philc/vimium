
cleanUpRegexp = (re) ->
  re.toString()
    .replace /^\//, ''
    .replace /\/$/, ''
    .replace /\\\//g, "/"

DomUtils.documentReady ->
  html = []
  for engine in CompletionEngines[0...CompletionEngines.length-1]
    engine = new engine
    html.push "<h4>#{engine.constructor.name}</h4>\n"
    html.push "<div class=\"engine\">"
    if engine.regexps
      html.push "<pre>"
      html.push "#{cleanUpRegexp re}\n" for re in engine.regexps
      html.push "</pre>"
    if engine.prefix
      html.push "<p>This uses the general Google completion engine, but adds the prefix \"<tt>#{engine.prefix.trim()}</tt>\" to the query.</p>"
    if engine.example.searchUrl and engine.example.keyword
      engine.example.description ||= engine.constructor.name
      html.push "<p>"
      html.push "Example:"
      html.push "<pre>"
      html.push "#{engine.example.keyword}: #{engine.example.searchUrl} #{engine.example.description}"
      html.push "</pre>"
      html.push "</p>"
    html.push "</div>"

  document.getElementById("engineList").innerHTML = html.join ""


