## External Commands

This is a demo extension for the Vimium `sendMessage` command.

Examples:

    map ea sendMessage name=focusFirstAudibleTab extension=ohmajiahfhgmmijaombnjclabhjlbfon
    map eh sendMessage name=showAlert message=Message
    map el sendMessage name=hover hint
    map eu sendMessage name=unhover

If the `extension` command options is set, then `sendMessage` uses
[cross-extension messaging](https://developer.chrome.com/extensions/messaging#external).
Otherwise, `window.postMessage()` is used.

If the `hint` command options is set, then Vimium first uses link-hints mode to
identify an element, and then sends the message. The message then contains
property `elementIndex` identifying the position of the element within the document:

```coffeescript
element = document.documentElement.getElementsByTagName("*")[message.elementIndex]
```

External commands can also be implemented in suitable TamperMonkey user scripts.
