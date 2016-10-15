Commands =
  sayHello:
    description: "Say hello."
    command: (options) ->
      alert "Hello!"

if chrome?.extension?.getBackgroundPage?() != window
  #  This is a content window; add listener.
  window.addEventListener "message", (request) ->
    Commands[request.data?.name]?.command request.data

else
  # This is the background page; show some instructions.
  console.log "\n# Content-page commands:"
  for own name, command of Commands
    console.log "# #{command.description}\n  map X sendMessage name=#{name}"
