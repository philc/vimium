handlers =
	#
	# This handler sets the textContent of the element.
	#
	"data-i18n-content": (element, attributeValue, handler) ->
		if handler(attributeValue)
			element.innerHTML = handler(attributeValue)

	#
    # This is used to set HTML attributes and DOM properties,. The syntax is:
    #  attributename:key;
    #  .domProperty:key;
    #  .nested.dom.property:key
    #
	"data-i18n-values": (element, attributeValue, handler) ->
		parts = attributeValue.replace(/\s/g, '').split(/;/);
		for part in parts
			a=part.match(/^([^:]+):(.+)$/)
			if(a)
				propName = a[1];
				propExpr = a[2];

			# Ignore missing properties
			if(handler(propExpr))
				value = handler(propExpr);
				if(propName.charAt(0)=='.')
					path = propName.slice(1).split('.');
					object = element;
					object = object[path.shift()] while(object && path.length > 1)
					if(object)
						object[path] = value;
						# In case we set innerHTML (ignoring others) we need to
                		# recursively check the content
						process(element, handler) if path == 'innerHTML'
				else
					element.setAttribute(propName, value);
			else
				console.warn('data-i18n-values: Missing value for "'+ propExpr+'"')
		null

attributeNames = []
attributeNames.push(key) for key of handlers

selector = '['+attributeNames.join('],[')+']'

#
# Processes a DOM tree with the {@code fn} function.
#
process = (node, handler) ->
		elements = node.querySelectorAll(selector);
		for element in elements
			for name in attributeNames
				att = element.getAttribute(name);
				handlers[name](element, att, handler) if att != null
		null
		
i18n =
	process: process
		
root = exports ? window
root.i18n = i18n
