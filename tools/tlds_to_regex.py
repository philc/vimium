import re
import sys
import codecs

def js_str_chunks(l, n):
  tmp = []
  size = 0
  for x in l:
    char_size = len(repr(x)) - 3
    if size + char_size > n:
      yield repr(''.join(tmp))[1:]
      tmp = []
      size = 0
    tmp += x
    size += char_size
  yield repr(''.join(tmp))[1:]

tlds = (line.strip() for line in codecs.open(sys.argv[1], 'r', 'utf-8')
        if line.strip() and not line.startswith('//'))

regex = '\\.(%s)$' % '|'.join(re.escape(t) for t in tlds)
print 'var tldRegex = new RegExp(\n%s\n);' \
        % '+\n'.join('  %s' % line for line in js_str_chunks(regex, 70))

