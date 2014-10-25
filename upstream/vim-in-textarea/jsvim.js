/* (c) jakub.mikians@gmail.com 2012, 2013 */

/* commented parts starting with //ext// should make crossrider extension out
 * of this script  */

//ext//appAPI.ready(function($) {

/*===================================================================*/
/* Command tree */

function Node(data) {
  this.set_choice = function( option, node, data ) {
    this.nodes[ option ] = {node: node, data: data}
    return this
  }

  this.get_choice = function( option ) {
    return this.nodes[option]
  }

  this.get_choice_node = function( option ) {
    var x = this.get_choice( option )
    return (x === undefined) ? undefined : x.node
  }

  this.is_leaf = function() {
    return is_empty_object( this.nodes ) 
  }

  this.set_choices = function( choices ) {
    for (var key in choices)
      if (choices.hasOwnProperty(key)) {
        var val = choices[key]
        if ( val instanceof Array ) {
          this.set_choice( key, val[0], val[1] )
        } else {
          this.set_choice( key, val )
        }
      }
    return this
  }

  this.data = data
  this.nodes = {}
}

var merge_dict = function( dict_a, dict_b ) {
  var r = {}

  var clone = function( src ) {
    for (var p in src)
      if (src.hasOwnProperty(p))
        r[p] = src[p]
  }

  clone(dict_a)
  if (dict_b !== undefined) clone(dict_b)

  return r
}

var is_empty_object = function(e) {
  for (var prop in e) if (e.hasOwnProperty(prop)) return false;
    return true;
}

/*===================================================================*/
/* VIM class and other */

var COMMAND = 'COMMAND'
var INSERT = 'INSERT'
var VISUAL = 'VISUAL'

var NREPEATS_LIMIT = 100
var UNDO_DEPTH = 100


var _proxy = function( func, context ) {
  return function(){
    return func.apply( context, arguments )
  }
}

var __special_keys = {
   8:'Backspace',
   9:'Tab',
  13:'Enter',
  27:'Escape',
  33:'PageUp',
  34:'PageDown',
  35:'End',
  36:'Home',
  37:'Left',
  38:'Up',
  39:'Right',
  40:'Down',
  45:'Insert',
  46:'Delete',
}

function VIM(ctrees) {
  this.attach_to = function(m_selector) {
    this.m_selector = m_selector
    m_selector.onkeydown = _proxy( this.on_keydown, this)
    m_selector.onkeypress = _proxy( this.on_keypress, this)
    this.reset()
//ext//    window.__refocus = true
  }

  this.on_keydown = function(event){
    var p 
    var m = __special_keys[ event.keyCode ]
    if (undefined === m ) {
      p = true
    } else {
      p = this.on_key( '<'+m+'>', event )
    }
    return p
  }

  this.on_keypress = function(event){
    var m = String.fromCharCode( event.keyCode )
    var p = this.on_key( m, event )
    return p
  }
  
  this.on_key = function(c, event) {
    this.log('"' + c + '"')
    var pass_keys
    if ('<Escape>' === c) {
      this.reset()
      pass_keys = false
    }
    else if ( this.is_mode(INSERT) ) {
      if (c === '<Enter>') {
        this.enter_auto_indent()
        pass_keys = false
      } else {
        pass_keys = true
      }
    }
    else if (c !== null) {
      this.accept_key( c )
      pass_keys = false
    }

    if ( false === pass_keys ) {
      event.preventDefault()
      event.stopPropagation() 
    }
    return pass_keys
  }

  this.enter_auto_indent = function() {
    var text = this.get_text()
    var pos = this.get_pos()
    
    var xs = select_line(text, pos)
    var n_spaces = count_space_from( text, xs[0] )
    var local_pos = pos - xs[0]
    n_spaces = (local_pos < n_spaces) ? local_pos : n_spaces
    var t = "\n" + repeat_str(' ', n_spaces)
    text = insert_at( text, t, pos )
    
    this.set_text( text )
    this.set_pos( pos + t.length )
  }

  this.set_mode = function(mode) {
    this.log("set_mode " + mode)
    if (this.m_mode === COMMAND && mode === VISUAL) {
      // do not change when comming from PENDING - would affect 'viw'
      this.m_selection_from = this.get_pos()
    }
    this.m_mode = mode
    if (this.on_set_mode !== undefined) this.on_set_mode(this)
  }

  this.insert_to_clipboard = function(text) {
    this.log('insert_to_clipboard len: ' + text.length)
    if (this.m_allow_clipboard_reset) {
      this.m_allow_clipboard_reset = false
      this.m_buffer = ''
    }
    this.m_buffer += text
  }

  /* This is used to distinguish between "2daw" and "dawdaw". In first case,
   * both lines should be put into the buffer, and in the second case - only
   * the line deleted at second "daw", overwriting the line from first "daw" */
  this.allow_clipboard_reset = function(text) {
    this.m_allow_clipboard_reset = true
  }

  this.get_clipboard = function() { 
    return this.m_buffer 
  }

  this.save_undo_state = function() {
    var curr_text = this.get_text()
    var last_text = last( this.m_undo_stack )
    last_text = (last_text === undefined) ? '' : last_text.text

    if ( curr_text !== last_text ) {
      var t = {text: curr_text, pos: this.get_pos()}
      this.m_undo_stack.push( t )
      if (this.m_undo_stack.length > UNDO_DEPTH ) {
        this.m_undo_stack.shift()
      }
      this.log('undo depth ' + this.m_undo_stack.length )
    }
  }

  this.is_mode = function(mode) {
    return this.m_mode === mode
  }

  this.reset = function() {
    this.reset_mode()
    this.reset_commands()
  }

  this.reset_mode = function() {
    this.set_mode( COMMAND )
  }

  this.reset_commands = function() {
    this.m_cnode = this.m_ctrees[ this.m_mode ]
    this.m_cdata = {}
    this.m_current_sequence = ''
  }

  this.get_pos = function() {
    return getCaret( document.activeElement )
  }

  this.get_text = function() {
    return this.m_selector.value
  }

  this.set_text = function(tx) {
    this.m_selector.value = tx
  }

  this.set_pos = function(k) {
    _select_pos( this.m_selector, k )
    if (this.on_set_pos !== undefined) this.on_set_pos(this)
  }

  this.select_current_line = function() {
    return select_line( this.get_text(), this.get_pos() )
  }

  this.accept_key = function(c) {
    this.m_current_sequence += c
    var x = this.m_cnode.get_choice(c)
    if (x === undefined) {
      this.log('(unknown sequence "'+this.m_current_sequence+'"')
      this.reset_commands()
    }
    else {
      this.m_cdata = merge_dict( this.m_cdata, x.data )
      this.m_cdata = merge_dict( this.m_cdata, x.node.data )
      this.m_cnode = x.node

      if (this.m_cnode.is_leaf()) {
        var nrepeats
        if (this.m_cdata.digit === undefined) {
          nrepeats = ( (this.m_digit_buffer === '') ? 1
                       : parseInt(this.m_digit_buffer))
          nrepeats = (nrepeats > NREPEATS_LIMIT) ? NREPEATS_LIMIT : 
                      ( (nrepeats < 1) ? 1 : nrepeats)
          this.m_digit_buffer = ''
        }
        else {
          nrepeats = 1
        }
        if (nrepeats !== 1) { this.log('n. repeats: ' + nrepeats) }

        this.allow_clipboard_reset()
        if ( ! this.m_cdata.dont_save_undo_state ) {
          this.save_undo_state()
        }
        for (var i = 0; i < nrepeats; i++ ) { 
          this.execute_leaf() 
        }
        this.reset_commands()
      }
    }
  }

  this.execute_leaf = function() {
    var fn = this.m_cdata.action
    if ( fn === undefined )  {
      this.log('ERROR: could not execute leaf!')
    } else {
      //fn.apply( this, [this, this.m_cdata] )
      fn( this, this.m_cdata )
    }
  }

  this.log = function(message){
    if (this.on_log !== undefined) {
      this.on_log(message)
    }
  }

  this.m_ctrees = build_sequence_trees() // this can be shared among all VIMs
  this.m_selector = null
  this.m_mode = undefined
  this.m_selection_from = undefined
  this.m_cnode = undefined
  this.m_current_sequence = ''
  this.m_digit_buffer = ''
  this.m_cdata = {} /* data merged during ctree traversal */
  this.m_undo_stack = []
  this.m_buffer = ''

  // callbacks, for extenal functions; e.g., for nice formatting
  this.on_set_mode = undefined
  this.on_set_pos = undefined
  this.on_log = undefined
} /* VIM END */

//==============================================================================

// http://stackoverflow.com/questions/263743/how-to-get-caret-position-in-textarea
function getCaret(el) { 
  if (el.selectionStart) { 
    return el.selectionStart; 
  } else if (document.selection) { 
    el.focus(); 

    var r = document.selection.createRange(); 
    if (r == null) { 
      return 0; 
    } 

    var re = el.createTextRange(), 
        rc = re.duplicate(); 
    re.moveToBookmark(r.getBookmark()); 
    rc.setEndPoint('EndToStart', re); 

    return rc.text.length; 
  }  
  return 0; 
}

/* 
based on
http://stackoverflow.com/questions/499126/jquery-set-cursor-position-in-text-area
*/
var _select_pos = function(el, pos) {
  if (el.setSelectionRange) {
    el.focus();
    el.setSelectionRange(pos, pos);
  } else if (el.createTextRange) {
    var range = el.createTextRange();
    range.collapse(true);
    range.moveEnd('character', pos);
    range.moveStart('character', pos);
    range.select();
  }
};


//=============================================================================

var node = function(x) {
  return new Node(x)
}

var build_sequence_trees = function() {
  var tree_command = build_tree_command_mode()
  var tree_visual = build_tree_visual_mode()
  return {COMMAND: tree_command,
          VISUAL: tree_visual}
}

var build_tree_command_mode = function() {
  var d_inside = function(fn) {
    return function(text, pos) {
      var xs = fn(text, pos)
      return (xs[1] === 0) ? xs : [xs[0] + 1, xs[1] - 2] 
    }
  }

  var d_in_line = function(fn){
    return function(text, pos) {
      var iline = select_line(text, pos)
      var line_pos = iline[0], line_len = iline[1]
      var line = text.substr( line_pos, line_len )
      var xs = fn( line, pos - line_pos )
      return [ xs[0] + line_pos, xs[1] ]
    }
  }

  var choices_ai = {
    'a': node()
      .set_choice('p', node({ select_func: d_with_whitespaces_after(select_paragraph) }))
      .set_choice('w', node({ select_func: find_word_with_spaces_after }))
      .set_choice('W', node({ select_func: d_with_spaces_after(find_word_plus) }))
      .set_choice("'", node({ select_func: d_in_line( select_quotes.partial("'")) }))
      .set_choice('"', node({ select_func: d_in_line( select_quotes.partial('"')) }))
      .set_choice('(', node({ select_func: select_bounds.partial('()') }))
      .set_choice(')', node({ select_func: select_bounds.partial('()') }))
      .set_choice('{', node({ select_func: select_bounds.partial('{}') }))
      .set_choice('}', node({ select_func: select_bounds.partial('{}') }))
      .set_choice('<', node({ select_func: select_bounds.partial('<>') }))
      .set_choice('>', node({ select_func: select_bounds.partial('<>') }))
      .set_choice('[', node({ select_func: select_bounds.partial('[]') }))
      .set_choice(']', node({ select_func: select_bounds.partial('[]') })) ,

    'i': node()
      .set_choice('p', node({ select_func: select_paragraph }))
      .set_choice('w', node({ select_func: find_word }))
      .set_choice('W', node({ select_func: find_word_plus }))
      .set_choice("'", node({ select_func: d_inside( d_in_line( select_quotes.partial("'"))) }))
      .set_choice('"', node({ select_func: d_inside( d_in_line( select_quotes.partial('"'))) }))
      .set_choice('(', node({ select_func: d_inside( select_bounds.partial('()')) }))
      .set_choice(')', node({ select_func: d_inside( select_bounds.partial('()')) }))
      .set_choice('{', node({ select_func: d_inside( select_bounds.partial('{}')) }))
      .set_choice('}', node({ select_func: d_inside( select_bounds.partial('{}')) }))
      .set_choice('<', node({ select_func: d_inside( select_bounds.partial('<>')) }))
      .set_choice('>', node({ select_func: d_inside( select_bounds.partial('<>')) }))
      .set_choice('[', node({ select_func: d_inside( select_bounds.partial('[]')) }))
      .set_choice(']', node({ select_func: d_inside( select_bounds.partial('[]')) })) ,
  }

  var _select_line = node( {select_func: select_line } )

  var _c = node()
    .set_choices( make_choices_for_navigation() )
    .set_choices( choices_ai )
    .set_choice('c', _select_line )
    .set_choice('w', node( {select_func: till_right_word_bound} ))
    .set_choice('W', node( {select_func: till_right_word_bound_plus} ))

  var _d = make_node_dy('d')
    .set_choices( choices_ai )

  var _y = make_node_dy('y')
    .set_choices( choices_ai )

  var _indent_inc = make_node_indent('>')
    .set_choices( choices_ai )

  var _indent_dec = make_node_indent('<')
    .set_choices( choices_ai )

  var _r = node()
    .set_choices( make_choices_for_navigation({action: act_move}))
    .set_choices( make_choices_for_digits() )
    .set_choice('a', node({action: act_append}))
    .set_choice('A', node({action: act_append_to_end}))
    .set_choice('c', _c,  {action: act_delete_range, mode: INSERT})
    .set_choice('C', node({action: act_delete_range, mode: INSERT,
                           move_func: move_to_line_end}))
    .set_choice('d', _d,  {action: act_delete_range, mode: COMMAND})
    .set_choice('D', node({action: act_delete_range, mode: COMMAND, 
                           move_func: move_to_line_end}))
    .set_choice('i', node({action: act_insert}))
    .set_choice('J', node({action: act_merge_lines}))
    .set_choice('o', node({action: act_insert_line_after}))
    .set_choice('O', node({action: act_insert_line_before}))
    .set_choice('p', node({action: act_paste_after}))
    .set_choice('P', node({action: act_paste_before}))
    .set_choice('s', node({action: act_delete_char, mode: INSERT}))
    .set_choice('u', node({action: act_undo, dont_save_undo_state: true}))
    .set_choice('v', node({action: act_visual_mode}))
    .set_choice('x', node({action: act_delete_char}))
    .set_choice('y', _y,  {action: act_yank_range})
    .set_choice('>', _indent_inc, {action: act_indent_increase} )
    .set_choice('<', _indent_dec, {action: act_indent_decrease} )

  return _r
}

var make_node_dy = function( line_char ) {
  var e = node()
    .set_choices( make_choices_for_navigation() )
    .set_choice( line_char, node( {select_func: select_line_nl} ) )
    .set_choice('w', node( {select_func: till_next_word} ))
    .set_choice('W', node( {select_func: till_next_word_plus} ))
  return e
}

var make_node_indent = function( line_char ) {
  var e = node()
    .set_choices( make_choices_for_navigation() )
    .set_choice( line_char, node( {select_func: select_line} ) )
  return e
}


var build_tree_visual_mode = function() {
  var _r = node()
    .set_choices( make_choices_for_navigation({action: act_move}) )
    .set_choices( make_choices_for_digits() )
    .set_choice('d', node({action: act_delete_current_selection, mode: COMMAND}) )
    .set_choice('c', node({action: act_delete_current_selection, mode: INSERT}) )
  return _r
}

var make_choices_for_navigation = function(params) {
  params = (params===undefined) ? {} : params
  var N = function(d) { return node( merge_dict( params, d) ) }

  var _g = node()
    .set_choice('g', N({move_func: move_to_very_beginning}))

  var ch = {
    '0': N({move_func: move_to_line_start}), 
    '$': N({move_func: move_to_line_end}),
    '<Left>':  N({move_func: move_left}),
    '<Down>':  N({move_func: move_down}),
    '<Up>':    N({move_func: move_up}),
    '<Right>': N({move_func: move_right}),
    'h':       N({move_func: move_left}),
    'j':       N({move_func: move_down}),
    'k':       N({move_func: move_up}),
    'l':       N({move_func: move_right}),
    '<Enter>': N({move_func: move_to_word_in_next_line}),
    '<Backspace>': N({move_func: move_left}),

    'w': N({move_func: move_to_next_word}),
    'W': N({move_func: move_to_next_word_plus}),
    'e': N({move_func: move_to_end_of_word}),
    'E': N({move_func: move_to_end_of_word_plus}),
    'b': N({move_func: move_to_prev_word}),
    'B': N({move_func: move_to_prev_word_plus}),
    'g': _g,
    'G': N({move_func: move_to_very_end}),
  }
  return ch
}

var make_choices_for_digits = function(){
  var xs = {}
  for (var i = 1; i < 10; i++) {
    var c = i.toString()
    xs[c] = node({action: act_accept_digit, digit: c})
  }
  xs['0'] = node({action: act_zero, digit: '0'})
  return xs
}

//=============================================================================

/* find_... , till_... and other selection functions return [pos,len] where pos
 * is position of the element and len is length of element. len can be 0 */

var find_word = function( text, pos ) {
  var m = '(\\s(?=\\S))|([^W](?=[W]))|(\\S(?=\\s))|([W](?=[^W]))'.replace(/W/g,'\\u0000-\\u002f\\u003a-\\u0040\\u005b-\\u0060\\u007b-\\u00bf')
  var p = new RegExp( m,'g' )
  return __find_regex_break( p, text, pos )
}

// non ascii unicode
///[\u0000-\u002f\u003a-\u0040\u005b-\u0060\u007b-\u00bf]/

var find_word_plus = function(text, pos) {
  var p = /(\s(?=\S))|(\S(?=\s))/g
  return __find_regex_break(p, text, pos)
}

var find_word_with_spaces_after = function(text, pos) {
  return d_with_spaces_after(find_word)(text, pos)
}

var d_with_spaces_after = function(fn) {
  return d_with_characters_after(fn, ' ')
}

var d_with_whitespaces_after = function(fn) {
  return d_with_characters_after(fn, '\n\s')
}

var d_with_characters_after = function(fn, characters){
  return function(text, pos) {
    var g = fn(text, pos)
    var n = count_space_from(text, g[0]+g[1], characters)
    return [ g[0], g[1] + n ]
  }
}


//var find_word_with_spaces_before = function(text, pos) {
//  var xs = find_word(text, pos)
//  var n = count_space_to(text, xs[0])
//  return [ xs[0]-n, xs[1]+n ]
//}

var find_word_plus_with_trailing_spaces = function(text, pos) {
  var g = find_word_plus(text, pos)
  var n = count_space_from(text, g[0]+g[1])
  return [ g[0], g[1] + n ]
}

var till_right_word_bound = function( text, pos ) {
  var xs = find_word( text, pos )
  return [ pos, xs[0] + xs[1] - pos ]
}


var till_right_word_bound_plus = function( text, pos ) {
  var xs = find_word_plus( text, pos )
  return [ pos, xs[0] + xs[1] - pos ]
}

//var till_left_word_bound = function( text, pos ) {
//  var xs = find_word( text, pos )
//  var len = pos - xs[0]
//  return [ xs[0], len ]
//}

var till_next_word = function(text, pos) {
  var g = find_word_with_spaces_after(text,pos)
  return [ pos, g[0] + g[1] - pos]
}

var till_next_word_plus = function(text, pos) {
  var g = find_word_plus_with_trailing_spaces(text,pos)
  return [ pos, g[0] + g[1] - pos ]
}


///* decorator - find a pattern with fn_find and latter find the trailing spaces */
//var with_trailing_spaces = function( fn_find ) { // todo: refactor, remove?
//  return function( text, pos ) {
//    var xs = fn_find(text, pos)
//    var t = regex_end_pos( /\s*/, text, {from: xs[1]} )
//    xs[1] = t
//    return xs
//  }
//}

var regex_end_pos = function( regex, text, opts ) {
  opts = (opts === undefined) ? {from:0} : opts
  var tx = text.substr( opts.from )
  var m = regex.exec(tx)
  var g = 0 // group === undefined ? 0 : group
  return m === null ? null : m.index + m[g].length + opts.from
}

var cut_slice = function( text, i0, i1 ) {
  var from, to
  if (i0 < i1 ) { from = i0; to = i1 } 
  else { from = i1; to = i0 }
  return { text: text.substr(0, from) + text.substr(to),
           cut:  text.substr(from, (to-from)),
           from: from, to: to }
}

/* return [start of the line, length] */
var select_line = function( text, pos ) {
  var ileft = trailing_nl( text, pos )
  var iright = leading_nl( text, pos )
  return [ileft, iright - ileft]
}

var select_line_nl = function( text, pos ) {
  var ileft = trailing_nl( text, pos )
  var iright = leading_nl( text, pos )
  return [ileft, iright - ileft + 1 ]
}

var select_next_line = function( text, pos ) {
  var xs = select_line( text, pos )
  var k = xs[0]+xs[1]+1
  return ( k < text.length ) ? select_line( text, k ) : undefined
}

var select_prev_line = function( text, pos ) {
  var xs = select_line( text, pos )
  var k = xs[0] - 1
  return (k >= 0) ? select_line(text, k) : undefined
}

var select_bounds = function(bounds, text, pos) {
  var m_left = bounds.charAt(0)
  var m_right = bounds.charAt(1)
  var i_left, i_right

  if ( text.charAt(pos) == m_left ) {
    i_left = pos
  } else {
    var k = 1
    for( var i = pos - 1; i >= 0; i-- ) {
      var c = text.charAt(i)
      k += ((c === m_left) ? -1 : 0) + ((c === m_right) ? 1 : 0)
      if (k === 0 ) {
        i_left = i
        break
      }
    }
  }

  if ( text.charAt(pos) == m_right ) {
    i_right = pos
  } else {
    var k = 1
    for( var i = pos + 1; i < text.length; i++ ) {
      var c = text.charAt(i)
      k += ((c === m_left) ? 1 : 0) + ((c === m_right) ? -1 : 0)
      if (k === 0) {
        i_right = i
        break
      }
    }
  }

  return ((i_right === undefined) || (i_left === undefined)) ? 
           [pos,0] : 
           [i_left, i_right - i_left + 1]
}

var select_quotes = function(quote, text, pos) {
  var xs = __select_quotes(quote, text, pos)
  var i_left = xs[0], i_right = xs[1]
  return ( (i_left === undefined) || (i_right === undefined) ) ? 
            [pos,0] : 
            [i_left, i_right - i_left + 1] 
}

var __select_quotes = function(quote, text, pos) {
  var i_left, i_right
  for(var i = pos; i >= 0; i--) {
    //if (text.charAt(i) === quote) {
    if (text.substr(i, quote.length) === quote) {
      i_left = i
      break
    }
  }
  for(var i = pos + 1; i < text.length; i++) {
    //if (text.charAt(i) === quote) {
    if (text.substr(i, quote.length) === quote) {
      i_right = i
      break
    }
  }
  return [i_left, i_right]
}

var select_paragraph = function(text, pos) {
  var regex = /\n\s*\n/g
  return __find_regex(regex, text, pos)
}

var __find_regex = function(regex, text, pos ) {
  var m, ileft = 0, iright
  while ( (m=regex.exec(text)) !== null ) {
    var i = m.index + m[0].length
    if ((ileft === undefined) || (i <= pos)) {
      ileft = i
    }
    i = m.index
    if ((iright === undefined) && (i > pos)) {
      iright = i
    }
  }
  iright = (iright === undefined) ? (text.length) : iright
  return [ileft, iright - ileft]
}

/* todo: merge __find_regex and __find_regex_break */
var __find_regex_break = function( regex, text, pos ) {
  var m, ileft = 0, iright
  while ( (m=regex.exec(text)) !== null ) {
    var i = m.index + 1
    if ((ileft === undefined) || (i <= pos)) {
      ileft = i
    }
    if ((iright === undefined) && (i > pos)) {
      iright = i
    }
  }
  iright = (iright === undefined) ? (text.length) : iright
  return [ileft, iright - ileft]
}

var trailing_nl = function ( text, pos ) {
  var i = trailing_char( text, pos, "\n" )
  return (i===undefined) ? 0 : i
}

var leading_nl = function ( text, pos ) {
  var i = leading_char( text, pos, "\n" )
  return (i===undefined) ? text.length : i
}

var trailing_char = function( text, pos, character ) {
  var t
  for ( var i = (pos-1); i >= 0; i-- ) {
    if ( text.charAt(i) == character ) {
      t = i + 1
      break
    }
  }
  return t
}

var leading_char = function(text, pos, character) {
  var t
  for (var i = pos; i < text.length; i++ ) {
    if (text.charAt(i) == character) {
      t = i
      break
    }
  }
  return t
}

/* Decorator, skips spaces at position and starts searching from after the
 * spaces */
var skip_spaces = function(search_func) {
  return function(text, pos) {
    var k = count_space_from( text, pos )
    var xs = search_func( text, k + pos )
    return xs
  }
}

var count_space_from = function(text, pos, characters) {
  characters = (characters===undefined) ? (' ') : characters
  var r = new RegExp('^['+characters+']+')
  var m = r.exec(text.substr(pos))
  return (m===null) ? 0 : m[0].length
}

var count_space_to = function(text,pos) {
  var k
  if (pos > text.length) {
    k = 0
  } else {
    var m = /[ ]+$/.exec(text.substr(0,pos))
    k = (m===null) ? 0 : m[0].length
  }
  return k
}

var insert_at = function( base, chunk, pos ) {
  return base.slice(0,pos).concat( chunk ).concat( base.slice(pos) )
}

var repeat_str = function( str, n_repeats ) {
  return (new Array(n_repeats+1)).join( str )
}

var last = function(xs, def) {
  return (xs.length > 0) ? ( xs[xs.length-1] ) : def
}

var insert_line_after_auto_indent = function(text, pos) {
  var xs = select_line( text, pos )
  var k = count_space_from( text, xs[0] )
  var t = "\n" + repeat_str(" ", k)
  var q = {}
  q.text = insert_at( text, t, xs[0] + xs[1] )
  q.pos = xs[0] + xs[1] + k + 1
  return q
}

Function.prototype.partial = function() {
  var base_args = to_array(arguments),
      base_fn = this
  return function(){
    var next_args = to_array(arguments)
    return base_fn.apply(this, base_args.concat(next_args))
  }
}

var to_array = function( args ) {
  return Array.prototype.slice.call(args, 0)
}

/* ACTIONS -- various commands */

var act_insert_line_after = function(vim, cdata) {
  var text = vim.get_text()
  var pos = vim.get_pos()
  var q = insert_line_after_auto_indent( text, pos )
  vim.set_text( q.text )
  vim.set_pos( q.pos )
  vim.set_mode( INSERT )
}

var act_insert_line_before = function(vim, cdata) {
  var text = vim.get_text()
  var pos = vim.get_pos()
  var xs = select_line( text, pos )
  var k = count_space_from( text, xs[0] )
  var t = repeat_str(" ", k) + "\n"
  text = insert_at( text, t, xs[0] )
  vim.set_text( text )
  vim.set_pos( xs[0] + k )
  vim.set_mode( INSERT )
}

var act_move = function(vim, cdata) {
  var p = cdata.move_func.apply( vim, [vim.get_text(), vim.get_pos()] )
  vim.set_pos( p )
}

var act_accept_digit = function(vim, cdata) {
  vim.m_digit_buffer += cdata.digit
}

/* zero is handled separately, because it can be both "go to start of the
 * line" and "insert 0 to digit buffer" */
var act_zero = function(vim, cdata) {
  if (vim.m_digit_buffer === '') {
    var s = vim.select_current_line()
    vim.set_pos( s[0] )
  } else {
    vim.m_digit_buffer += cdata.digit
  }
}

var act_delete_range = function(vim, cdata) {
  vim.log('delete range')
  var t = __yank(vim, cdata)
  vim.set_text( t.text )
  vim.set_pos( t.from )
  vim.set_mode( cdata.mode ) 
}

var act_yank_range = function(vim, cdata) {
  vim.log('yank range')
  var t = __yank(vim, cdata)
  vim.set_pos( t.from )
}

var __yank = function(vim, cdata) {
  var xs = selection_with.apply( vim, [ cdata, vim.get_text(), vim.get_pos() ] ) // todo, clean 
  var t = cut_slice( vim.get_text(), xs[0], xs[0] + xs[1] )
  vim.insert_to_clipboard( t.cut )
  return t
}

/* use either select_func or move_func parameter */
var selection_with = function( cdata, text, pos ) {
  var fn, xs
  fn = cdata.select_func
  if (fn === undefined) {
    fn = cdata.move_func
    var k = fn.apply( this, [ text, pos ] )
    var len = k - pos
    xs = (len >= 0) ?  [pos, len] : [pos + len, -len]
  }
  else {
    xs = fn.apply( this, [ text, pos ] )
  }
  return xs
}

var act_delete_char = function(vim, cdata) {
  var p = vim.get_pos()
  var t = vim.get_text()
  vim.set_text( t.substr(0,p) + t.substr(p+1) )
  vim.set_pos( p )
  vim.insert_to_clipboard( t.substr(p,1) )
  if (cdata.mode !== undefined) {
    vim.set_mode(INSERT)
  }
}

var act_append = function(vim, cdata) {
  vim.log('append')
  var xs = vim.select_current_line()
  var p = vim.get_pos()
  vim.set_pos( p + (p == (xs[0] + xs[1]) ? 0 : 1) ) /* don't move at the end of line*/
  vim.set_mode(INSERT)
}

var act_append_to_end = function(vim, cdata) {
  vim.log('append to end')
  var xs = vim.select_current_line()
  vim.set_pos( xs[0] + xs[1] ) 
  vim.set_mode(INSERT)
}

var act_insert = function(vim, cdata) {
  vim.log('insert')
  vim.set_mode(INSERT)
}

var act_delete_current_selection = function(vim, cdata) {
  vim.log('delete current selection')
  var t = cut_slice( vim.get_text(), vim.m_selection_from, vim.get_pos() )
  vim.set_text( t.text)
  vim.set_pos( t.from )
  vim.set_mode(cdata.mode)
  vim.insert_to_clipboard( t.cut )
}

var act_visual_mode = function(vim, cdata) {
  vim.log('act_visual_mode')
  vim.set_mode( VISUAL )
}

var act_undo = function(vim, cdata) {
  if (vim.m_undo_stack.length > 0) {
    vim.log('act_undo')
    var u = vim.m_undo_stack.pop()
    vim.set_text( u.text )
    vim.set_pos( u.pos )
  }
}

var act_paste_after = function(vim, cdata) {
  var pos = vim.get_pos()
  __paste(vim, cdata)
  vim.set_pos( pos + vim.get_clipboard().length )
}

var act_paste_before = function(vim, cdata){
  var pos = vim.get_pos()
  __paste(vim, cdata)
  vim.set_pos( pos )
}

var __paste = function(vim, cdata) {
  var pos = vim.get_pos()
  var buff = vim.get_clipboard()
  var t = vim.get_text()
  vim.log('act_paste, length: ' + buff.length )
  vim.set_text( t.substr(0, pos) + buff + t.substr(pos) )
}

var act_merge_lines = function(vim, cdata) {
  vim.log('act_merge_lines')
  var pos = vim.get_pos()
  var t = vim.get_text()
  var xs = select_line( t, pos )
  var endl = xs[0] + xs[1]
  t = t.substr( 0, endl ) + t.substr( endl + 1 )
  vim.set_text( t )
  vim.set_pos( endl )
}

var act_indent_increase = function(vim, cdata) {
  vim.log('act_indent_increase')
  __alter_selection(vim, cdata, function(t){return t.replace(/^/gm, ' ')} )
}

var act_indent_decrease = function(vim, cdata) {
  vim.log('act_indent_decrease')
  __alter_selection(vim, cdata, function(t){return t.replace(/^ /gm, '')} )
}

var __alter_selection = function(vim, cdata, func) {
  var xs = selection_with.apply( vim, [ cdata, vim.get_text(), vim.get_pos() ] )
  xs = expand_to_line_start( vim.get_text(), xs )
  var g = cut_with( vim.get_text(), xs )
  g.mid = func( g.mid ) 
  var new_text = g.left + g.mid + g.right
  vim.set_text( new_text )
  vim.set_pos( xs[0] + count_space_from(new_text, xs[0]) )
}

var expand_to_line_start = function(text, range) {
  var xs = select_line( text, range[0] )
  var off = range[0] - xs[0]
  return [xs[0], range[1] + off ]
}

var cut_with = function(text, range) {
  var pos = range[0], len = range[1]
  return { left: text.substr(0,pos),
           mid: text.substr(pos,len),
           right: text.substr(pos+len) }
}

//ext//var act_unfocus = function(vim, cdata) {
//ext//  vim.log('--unfocus--')
//ext//  window.__refocus = false
//ext//  vim.m_selector.blur()
//ext//}
//ext//
/* MOVE -- move functions, are launched in VIM context */

var move_right = function(text, pos) {
  return (pos < text.length) ? (pos+1) : (pos)
}

var move_left = function(text, pos) {
  return (pos>0) ? (pos-1) : (pos)
}

var move_down = function(text, pos) {
  var lnext = select_next_line(text, pos)
  if (lnext !== undefined ) {
    var lcurr = select_line(text, pos)
    var offset = pos - lcurr[0]
    offset = (offset >= lnext[1]) ? (lnext[1]) : offset
    pos = offset + lnext[0]
  }
  return pos
}

var move_up = function(text, pos) {
  var lprev = select_prev_line(text, pos)
  if (lprev !== undefined ) {
    var lcurr = select_line(text, pos)
    var offset = pos - lcurr[0]
    offset = (offset >= lprev[1]) ? (lprev[1]) : offset
    pos = offset + lprev[0]
  }
  return pos
}

var move_to_next_word = function(text, pos) {
  var xs = find_word_with_spaces_after(text, pos)
  return xs[0] + xs[1]
}

var move_to_next_word_plus = function(text, pos) {
  var xs = find_word_plus_with_trailing_spaces( text, pos )
  return xs[0] + xs[1]
}

var move_to_end_of_word = function(text, pos) {
  var xs = skip_spaces(find_word)( text, pos )
  return xs[0] + xs[1]
}

var move_to_end_of_word_plus = function(text, pos) {
  var xs = skip_spaces(find_word_plus)( text, pos )
  return xs[0] + xs[1]
}

var move_to_prev_word = function(text, pos) {
  var k = count_space_to(text, pos) + 1
  var xs = find_word(text,pos - k)
  return xs[0]
}

var move_to_prev_word_plus = function(text, pos) {
  var k = count_space_to(text, pos) + 1
  var xs = find_word_plus(text,pos - k)
  return xs[0]
}

var move_to_word_in_next_line = function(text, pos) {
  var new_pos
  var xline = select_next_line(text, pos)
  if (undefined === xline) {
    new_pos = pos
  } else {
    var nspaces = count_space_from( text, xline[0] )
    new_pos = xline[0] + nspaces
  }
  return new_pos
}

var move_to_very_beginning = function(text, pos) {
  return 0
}

var move_to_very_end = function(text, pos) {
  return text.length
}

var move_to_line_start = function(text, pos) {
  var s = select_line( text, pos ) 
  return s[0]
}

var move_to_line_end = function(text, pos) {
  var s = select_line( text, pos ) 
  return s[0] + s[1]
}

/* === READY === */

/* crossrider hook */

//ext// /* hook vim on click into textarea */
//ext// $(document).on('focus', 'textarea', function(event){
//ext//    console.log( 'vim: FOCUS' )
//ext//    $(this).off('keyup keydown keypress')
//ext//    //$(this).on('keyup keydown keypress', function(e){ 
//ext//    //  e.stopPropagation() 
//ext//    //  e.preventDefault()
//ext//    //  return false
//ext//    //})
//ext//
//ext//    if ( undefined === this.__vim_is_attached ) {
//ext//      var v = new VIM()
//ext//      v.on_log = function(m){console.log(m)}
//ext//      v.attach_to( this )
//ext//      this.__vim_is_attached = true
//ext//    } else {
//ext//      console.log('vim: already attached')
//ext//    }
//ext// })
//ext//
//ext// $(document).on('blur', 'textarea', function(event){
//ext//    //$(this).off('vim: keyup keydown keypress')
//ext//    if (true === window.__refocus) {
//ext//      console.log('blur: refocus')
//ext//      $(this).focus()
//ext//    } else {
//ext//      console.log('blur: don\'t refocus')
//ext//    }
//ext//
//ext//    return false
//ext// })
//ext//
//ext// $(document).on('click',function(event){
//ext//   console.log('vim: loose focus on click')
//ext//   window.__refocus = false
//ext//   $(this).focus()
//ext// })
//ext//
//ext//});
