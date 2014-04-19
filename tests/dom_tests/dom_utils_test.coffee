context "Check visibility",

  should "detect visible elements as visible", ->
    document.getElementById("test-div").innerHTML = """
    <div id='foo'>test</div>
    """
    assert.isTrue (DomUtils.getVisibleClientRect document.getElementById 'foo') != null

  should "detect display:none links as hidden", ->
    document.getElementById("test-div").innerHTML = """
    <a id='foo' style='display:none'>test</a>
    """
    assert.equal null, DomUtils.getVisibleClientRect document.getElementById 'foo'

  should "detect visibility:hidden links as hidden", ->
    document.getElementById("test-div").innerHTML = """
    <a id='foo' style='visibility:hidden'>test</a>
    """
    assert.equal null, DomUtils.getVisibleClientRect document.getElementById 'foo'

  should "detect elements nested in display:none elements as hidden", ->
    document.getElementById("test-div").innerHTML = """
    <div style='display:none'>
      <a id='foo'>test</a>
    </div>
    """
    assert.equal null, DomUtils.getVisibleClientRect document.getElementById 'foo'

  should "detect links nested in visibility:hidden elements as hidden", ->
    document.getElementById("test-div").innerHTML = """
    <div style='visibility:hidden'>
      <a id='foo'>test</a>
    </div>
    """
    assert.equal null, DomUtils.getVisibleClientRect document.getElementById 'foo'

  should "detect links outside viewport as hidden", ->
    document.getElementById("test-div").innerHTML = """
    <a id='foo' style='position:absolute;top:-2000px'>test</a>
    <a id='bar' style='position:absolute;left:2000px'>test</a>
    """
    assert.equal null, DomUtils.getVisibleClientRect document.getElementById 'foo'
    assert.equal null, DomUtils.getVisibleClientRect document.getElementById 'bar'

  should "detect links only partially outside viewport as visible", ->
    document.getElementById("test-div").innerHTML = """
    <a id='foo' style='position:absolute;top:-10px'>test</a>
    <a id='bar' style='position:absolute;left:-10px'>test</a>
    """
    assert.isTrue (DomUtils.getVisibleClientRect document.getElementById 'foo') != null
    assert.isTrue (DomUtils.getVisibleClientRect document.getElementById 'bar') != null

  should "detect opacity:0 links as hidden", ->
    document.getElementById("test-div").innerHTML = """
    <a id='foo' style='opacity:0'>test</a>
    """
    assert.equal null, DomUtils.getVisibleClientRect document.getElementById 'foo'

  should "detect links that contain only floated / absolutely-positioned divs as visible", ->
    document.getElementById("test-div").innerHTML = """
    <a id='foo'>
      <div style='float:left'>test</div>
    </a>
    """
    assert.isTrue (DomUtils.getVisibleClientRect document.getElementById 'foo') != null

    document.getElementById("test-div").innerHTML = """
    <a id='foo'>
      <div style='position:absolute;top:0;left:0'>test</div>
    </a>
    """
    assert.isTrue (DomUtils.getVisibleClientRect document.getElementById 'foo') != null

  should "detect links that contain only invisible floated divs as invisible", ->
    document.getElementById("test-div").innerHTML = """
    <a id='foo'>
      <div style='float:left;visibility:hidden'>test</div>
    </a>
    """
    assert.equal null, DomUtils.getVisibleClientRect document.getElementById 'foo'

  should "detect links inside opacity:0 elements as visible", ->
    # XXX This is an expected failure. See issue #16.
    document.getElementById("test-div").innerHTML = """
    <div style='opacity:0'>
      <a id='foo'>test</a>
    </div>
    """
    assert.isTrue (DomUtils.getVisibleClientRect document.getElementById 'foo') != null

  should "Detect links within SVGs as visible", ->
    # XXX this is an expected failure
    document.getElementById("test-div").innerHTML = """
    <svg>
      <a id='foo' xlink:href='http://www.example.com/'>
        <text x='0' y='68'>test</text>
      </a>
    </svg>
    """
    assert.equal null, DomUtils.getVisibleClientRect document.getElementById 'foo'
