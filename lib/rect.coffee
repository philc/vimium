# Commands for manipulating rects.
Rect =
  # Create a rect given the top left and bottom right corners.
  create: (x1, y1, x2, y2) ->
    bottom: y2
    top: y1
    left: x1
    right: x2
    width: x2 - x1
    height: y2 - y1

  copy: (rect) ->
    bottom: rect.bottom
    top: rect.top
    left: rect.left
    right: rect.right
    width: rect.width
    height: rect.height

  # Translate a rect by x horizontally and y vertically.
  translate: (rect, x = 0, y = 0) ->
    bottom: rect.bottom + y
    top: rect.top + y
    left: rect.left + x
    right: rect.right + x
    width: rect.width
    height: rect.height

  # Subtract rect2 from rect1, returning an array of rects which are in rect1 but not rect2.
  subtract: (rect1, rect2) ->
    # Bound rect2 by rect1
    rect2 = @create(
      Math.max(rect1.left, rect2.left),
      Math.max(rect1.top, rect2.top),
      Math.min(rect1.right, rect2.right),
      Math.min(rect1.bottom, rect2.bottom)
    )

    # If bounding rect2 has made the width or height negative, rect1 does not contain rect2.
    return [Rect.copy rect1] if rect2.width < 0 or rect2.height < 0

    #
    # All the possible rects, in the order
    # +-+-+-+
    # |1|2|3|
    # +-+-+-+
    # |4| |5|
    # +-+-+-+
    # |6|7|8|
    # +-+-+-+
    # where the outer rectangle is rect1 and the inner rectangle is rect 2. Note that the rects may be of
    # width or height 0.
    #
    rects = [
      # Top row.
      @create rect1.left, rect1.top, rect2.left, rect2.top
      @create rect2.left, rect1.top, rect2.right, rect2.top
      @create rect2.right, rect1.top, rect1.right, rect2.top
      # Middle row.
      @create rect1.left, rect2.top, rect2.left, rect2.bottom
      @create rect2.right, rect2.top, rect1.right, rect2.bottom
      # Bottom row.
      @create rect1.left, rect2.bottom, rect2.left, rect1.bottom
      @create rect2.left, rect2.bottom, rect2.right, rect1.bottom
      @create rect2.right, rect2.bottom, rect1.right, rect1.bottom
    ]

    rects.filter (rect) -> rect.height > 0 and rect.width > 0

  # Determine whether two rects overlap.
  intersects: (rect1, rect2) ->
    rect1.right > rect2.left and
    rect1.left < rect2.right and
    rect1.bottom > rect2.top and
    rect1.top < rect2.bottom

  # Determine whether two rects overlap, including 0-width intersections at borders.
  intersectsStrict: (rect1, rect2) ->
    rect1.right >= rect2.left and rect1.left <= rect2.right and
    rect1.bottom >= rect2.top and rect1.top <= rect2.bottom

  equals: (rect1, rect2) ->
    for property in ["top", "bottom", "left", "right", "width", "height"]
      return false if rect1[property] != rect2[property]
    true

  intersect: (rect1, rect2) ->
    @create (Math.max rect1.left, rect2.left), (Math.max rect1.top, rect2.top),
        (Math.min rect1.right, rect2.right), (Math.min rect1.bottom, rect2.bottom)

root = exports ? (window.root ?= {})
root.Rect = Rect
extend window, root unless exports?
