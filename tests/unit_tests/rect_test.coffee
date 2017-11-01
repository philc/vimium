require "./test_helper.js"
extend(global, require "../../lib/rect.js")

context "Rect",
  should "set rect properties correctly", ->
    [x1, y1, x2, y2] = [1, 2, 3, 4]
    rect = Rect.create x1, y1, x2, y2
    assert.equal rect.left, x1
    assert.equal rect.top, y1
    assert.equal rect.right, x2
    assert.equal rect.bottom, y2
    assert.equal rect.width, x2 - x1
    assert.equal rect.height, y2 - y1

  should "translate rect horizontally", ->
    [x1, y1, x2, y2] = [1, 2, 3, 4]
    x = 5
    rect1 = Rect.create x1, y1, x2, y2
    rect2 = Rect.translate rect1, x

    assert.equal rect1.left + x, rect2.left
    assert.equal rect1.right + x, rect2.right

    assert.equal rect1.width, rect2.width
    assert.equal rect1.height, rect2.height
    assert.equal rect1.top, rect2.top
    assert.equal rect1.bottom, rect2.bottom

  should "translate rect vertically", ->
    [x1, y1, x2, y2] = [1, 2, 3, 4]
    y = 5
    rect1 = Rect.create x1, y1, x2, y2
    rect2 = Rect.translate rect1, undefined, y

    assert.equal rect1.top + y, rect2.top
    assert.equal rect1.bottom + y, rect2.bottom

    assert.equal rect1.width, rect2.width
    assert.equal rect1.height, rect2.height
    assert.equal rect1.left, rect2.left
    assert.equal rect1.right, rect2.right

context "Rect subtraction",
  context "unchanged by rects outside",
    should "left, above", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create -2, -2, -1, -1

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "left", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create -2, 0, -1, 1

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "left, below", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create -2, 2, -1, 3

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "right, above", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create 2, -2, 3, -1

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "right", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create 2, 0, 3, 1

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "right, below", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create 2, 2, 3, 3

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "above", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create 0, -2, 1, -1

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "below", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create 0, 2, 1, 3

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

  context "unchanged by rects touching",
    should "left, above", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create -1, -1, 0, 0

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "left", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create -1, 0, 0, 1

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "left, below", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create -1, 1, 0, 2

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "right, above", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create 1, -1, 2, 0

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "right", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create 1, 0, 2, 1

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "right, below", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create 1, 1, 2, 2

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "above", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create 0, -1, 1, 0

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

    should "below", ->
      rect1 = Rect.create 0, 0, 1, 1
      rect2 = Rect.create 0, 1, 1, 2

      rects = Rect.subtract rect1, rect2
      assert.equal rects.length, 1
      rect = rects[0]
      assert.isTrue Rect.equals rect1, rect

  should "have nothing when subtracting itself", ->
    rect = Rect.create 0, 0, 1, 1
    rects = Rect.subtract rect, rect
    assert.equal rects.length, 0

  should "not overlap subtracted rect", ->
    rect = Rect.create 0, 0, 3, 3
    for x in [-2..2]
      for y in [-2..2]
        for width in [1..3]
          for height in [1..3]
            subtractRect = Rect.create x, y, (x + width), (y + height)
            resultRects = Rect.subtract rect, subtractRect
            for resultRect in resultRects
              assert.isFalse Rect.intersects subtractRect, resultRect

  should "be contained in original rect", ->
    rect = Rect.create 0, 0, 3, 3
    for x in [-2..2]
      for y in [-2..2]
        for width in [1..3]
          for height in [1..3]
            subtractRect = Rect.create x, y, (x + width), (y + height)
            resultRects = Rect.subtract rect, subtractRect
            for resultRect in resultRects
              assert.isTrue Rect.intersects rect, resultRect

  should "contain the  subtracted rect in the original minus the results", ->
    rect = Rect.create 0, 0, 3, 3
    for x in [-2..2]
      for y in [-2..2]
        for width in [1..3]
          for height in [1..3]
            subtractRect = Rect.create x, y, (x + width), (y + height)
            resultRects = Rect.subtract rect, subtractRect
            resultComplement = [Rect.copy rect]
            for resultRect in resultRects
              resultComplement = Array::concat.apply [],
                (resultComplement.map (rect) -> Rect.subtract rect, resultRect)
            assert.isTrue (resultComplement.length == 0 or resultComplement.length == 1)
            if resultComplement.length == 1
              complementRect = resultComplement[0]
              assert.isTrue Rect.intersects subtractRect, complementRect

context "Rect overlaps",
  should "detect that a rect overlaps itself", ->
    rect = Rect.create 2, 2, 4, 4
    assert.isTrue Rect.intersectsStrict rect, rect

  should "detect that non-overlapping rectangles do not overlap on the left", ->
    rect1 = Rect.create 2, 2, 4, 4
    rect2 = Rect.create 0, 2, 1, 4
    assert.isFalse Rect.intersectsStrict rect1, rect2

  should "detect that non-overlapping rectangles do not overlap on the right", ->
    rect1 = Rect.create 2, 2, 4, 4
    rect2 = Rect.create 5, 2, 6, 4
    assert.isFalse Rect.intersectsStrict rect1, rect2

  should "detect that non-overlapping rectangles do not overlap on the top", ->
    rect1 = Rect.create 2, 2, 4, 4
    rect2 = Rect.create 2, 0, 2, 1
    assert.isFalse Rect.intersectsStrict rect1, rect2

  should "detect that non-overlapping rectangles do not overlap on the bottom", ->
    rect1 = Rect.create 2, 2, 4, 4
    rect2 = Rect.create 2, 5, 2, 6
    assert.isFalse Rect.intersectsStrict rect1, rect2

  should "detect overlapping rectangles on the left", ->
    rect1 = Rect.create 2, 2, 4, 4
    rect2 = Rect.create 0, 2, 2, 4
    assert.isTrue Rect.intersectsStrict rect1, rect2

  should "detect overlapping rectangles on the right", ->
    rect1 = Rect.create 2, 2, 4, 4
    rect2 = Rect.create 4, 2, 5, 4
    assert.isTrue Rect.intersectsStrict rect1, rect2

  should "detect overlapping rectangles on the top", ->
    rect1 = Rect.create 2, 2, 4, 4
    rect2 = Rect.create 2, 4, 4, 5
    assert.isTrue Rect.intersectsStrict rect1, rect2

  should "detect overlapping rectangles on the bottom", ->
    rect1 = Rect.create 2, 2, 4, 4
    rect2 = Rect.create 2, 0, 4, 2
    assert.isTrue Rect.intersectsStrict rect1, rect2

  should "detect overlapping rectangles when second rectangle is contained in first", ->
    rect1 = Rect.create 1, 1, 4, 4
    rect2 = Rect.create 2, 2, 3, 3
    assert.isTrue Rect.intersectsStrict rect1, rect2

  should "detect overlapping rectangles when first rectangle is contained in second", ->
    rect1 = Rect.create 1, 1, 4, 4
    rect2 = Rect.create 2, 2, 3, 3
    assert.isTrue Rect.intersectsStrict rect2, rect1

