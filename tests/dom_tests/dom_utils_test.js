context("DOM content loaded", () => {
  // The DOM content has already loaded, this should be called immediately.
  should("call callback immediately.", () => {
    let called = false;
    DomUtils.documentReady(() => called = true);
    assert.isTrue(called);
  });

  // See ./dom_tests.html; the callback there was installed before the document was ready.
  should("already have called callback embedded in test page.", () => {
    assert.isTrue(window.documentReadyListenerCalled);
  });
});

context("Check visibility", () => {
  should("detect visible elements as visible", () => {
    document.getElementById("test-div").innerHTML = `\
      <div id='foo'>test</div>`;
    assert.isTrue((DomUtils.getVisibleClientRect(document.getElementById("foo"), true)) !== null);
  });

  should("detect display:none links as hidden", () => {
    document.getElementById("test-div").innerHTML = `\
      <a id='foo' style='display:none'>test</a>`;
    assert.equal(null, DomUtils.getVisibleClientRect(document.getElementById("foo"), true));
  });

  should("detect visibility:hidden links as hidden", () => {
    document.getElementById("test-div").innerHTML = `\
      <a id='foo' style='visibility:hidden'>test</a>`;
    assert.equal(null, DomUtils.getVisibleClientRect(document.getElementById("foo"), true));
  });

  should("detect elements nested in display:none elements as hidden", () => {
    document.getElementById("test-div").innerHTML = `\
      <div style='display:none'>
        <a id='foo'>test</a>
      </div>`;
    assert.equal(null, DomUtils.getVisibleClientRect(document.getElementById("foo"), true));
  });

  should("detect links nested in visibility:hidden elements as hidden", () => {
    document.getElementById("test-div").innerHTML = `\
      <div style='visibility:hidden'>
        <a id='foo'>test</a>
      </div>`;
    assert.equal(null, DomUtils.getVisibleClientRect(document.getElementById("foo"), true));
  });

  should("detect links outside viewport as hidden", () => {
    document.getElementById("test-div").innerHTML = `\
      <a id='foo' style='position:absolute;top:-2000px'>test</a>
      <a id='bar' style='position:absolute;left:2000px'>test</a>`;
    assert.equal(null, DomUtils.getVisibleClientRect(document.getElementById("foo"), true));
    assert.equal(null, DomUtils.getVisibleClientRect(document.getElementById("bar"), true));
  });

  should("detect links only partially outside viewport as visible", () => {
    document.getElementById("test-div").innerHTML = `\
      <a id='foo' style='position:absolute;top:-10px'>test</a>
      <a id='bar' style='position:absolute;left:-10px'>test</a>`;
    assert.isTrue((DomUtils.getVisibleClientRect(document.getElementById("foo"), true)) !== null);
    assert.isTrue((DomUtils.getVisibleClientRect(document.getElementById("bar"), true)) !== null);
  });

  should("detect links that contain only floated / absolutely-positioned divs as visible", () => {
    document.getElementById("test-div").innerHTML = `\
      <a id='foo'>
        <div style='float:left'>test</div>
      </a>`;
    assert.isTrue((DomUtils.getVisibleClientRect(document.getElementById("foo"), true)) !== null);

    document.getElementById("test-div").innerHTML = `\
      <a id='foo'>
        <div style='position:absolute;top:0;left:0'>test</div>
      </a>`;
    assert.isTrue((DomUtils.getVisibleClientRect(document.getElementById("foo"), true)) !== null);
  });

  should("detect links that contain only invisible floated divs as invisible", () => {
    document.getElementById("test-div").innerHTML = `\
      <a id='foo'>
        <div style='float:left;visibility:hidden'>test</div>
      </a>`;
    assert.equal(null, DomUtils.getVisibleClientRect(document.getElementById("foo"), true));
  });

  should(
    "detect font-size: 0; and display: inline; links when their children are display: inline",
    () => {
      // This test represents the minimal test case covering issue #1554.
      document.getElementById("test-div").innerHTML = `\
        <a id='foo' style='display: inline; font-size: 0px;'>
          <div style='display: inline; font-size: 16px;'>test</div>
        </a>`;
      assert.isTrue((DomUtils.getVisibleClientRect(document.getElementById("foo"), true)) !== null);
    },
  );

  should("detect links inside opacity:0 elements as visible", () => {
    // XXX This is an expected failure. See issue #16.
    document.getElementById("test-div").innerHTML = `\
      <div style='opacity:0'>
        <a id='foo'>test</a>
      </div>`;
    assert.isTrue((DomUtils.getVisibleClientRect(document.getElementById("foo"), true)) !== null);
  });
});

context("getClientRectsForAreas", () => {
  let img, area;
  setup(() => {
    img = document.createElement("img");
    area = document.createElement("area");
  });

  should("return the associated rect for an image map", () => {
    area.setAttribute("coords", "1,2,3,4");
    const result = DomUtils.getClientRectsForAreas(img, [area]);
    assert.equal([{ element: area, rect: Rect.create(1, 2, 3, 4) }], result);
  });

  should("skip when a map's coords are malformed", () => {
    area.setAttribute("coords", "1,2,3"); // This is only 3 coords rather than 4.
    assert.equal([], DomUtils.getClientRectsForAreas(img, [area]));
    area.setAttribute("coords", "1,2,3,junk-value");
    assert.equal([], DomUtils.getClientRectsForAreas(img, [area]));
  });
});

// NOTE(philc): This test doesn't pass on puppeteer. It's unclear from the XXX comment if it's
// supposed to.
// should("Detect links within SVGs as visible"), () => {
//   # XXX this is an expected failure
//   document.getElementById("test-div").innerHTML = """
//   <svg>
//     <a id='foo' xlink:href='http://www.example.com/'>
//       <text x='0' y='68'>test</text>
//     </a>
//   </svg>
//   """
//   assert.equal(null, (DomUtils.getVisibleClientRect (document.getElementById 'foo'), true));
// }
