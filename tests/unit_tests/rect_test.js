import "./test_helper.js";
import "../../lib/rect.js";

context("Rect", () => {
  should("set rect properties correctly", () => {
    const [x1, y1, x2, y2] = [1, 2, 3, 4];
    const rect = Rect.create(x1, y1, x2, y2);
    assert.equal(rect.left, x1);
    assert.equal(rect.top, y1);
    assert.equal(rect.right, x2);
    assert.equal(rect.bottom, y2);
    assert.equal(rect.width, x2 - x1);
    assert.equal(rect.height, y2 - y1);
  }),

  should("translate rect horizontally", () => {
    const [x1, y1, x2, y2] = [1, 2, 3, 4];
    const x = 5;
    const rect1 = Rect.create(x1, y1, x2, y2);
    const rect2 = Rect.translate(rect1, x);

    assert.equal(rect1.left + x, rect2.left);
    assert.equal(rect1.right + x, rect2.right);

    assert.equal(rect1.width, rect2.width);
    assert.equal(rect1.height, rect2.height);
    assert.equal(rect1.top, rect2.top);
    assert.equal(rect1.bottom, rect2.bottom);
  });

  should("translate rect vertically", () => {
    const [x1, y1, x2, y2] = [1, 2, 3, 4];
    const y = 5;
    const rect1 = Rect.create(x1, y1, x2, y2);
    const rect2 = Rect.translate(rect1, undefined, y);

    assert.equal(rect1.top + y, rect2.top);
    assert.equal(rect1.bottom + y, rect2.bottom);

    assert.equal(rect1.width, rect2.width);
    assert.equal(rect1.height, rect2.height);
    assert.equal(rect1.left, rect2.left);
    assert.equal(rect1.right, rect2.right);
  })
});

context("Rect subtraction", () => {
  context("unchanged by rects outside", () => {
    should("left, above", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(-2, -2, -1, -1);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("left", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(-2, 0, -1, 1);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("left, below", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(-2, 2, -1, 3);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("right, above", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(2, -2, 3, -1);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("right", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(2, 0, 3, 1);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("right, below", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(2, 2, 3, 3);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("above", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(0, -2, 1, -1);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("below", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(0, 2, 1, 3);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    })
  }),

  context("unchanged by rects touching", () => {
    should("left, above", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(-1, -1, 0, 0);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("left", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(-1, 0, 0, 1);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("left, below", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(-1, 1, 0, 2);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("right, above", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(1, -1, 2, 0);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("right", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(1, 0, 2, 1);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("right, below", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(1, 1, 2, 2);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("above", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(0, -1, 1, 0);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });

    should("below", () => {
      const rect1 = Rect.create(0, 0, 1, 1);
      const rect2 = Rect.create(0, 1, 1, 2);

      const rects = Rect.subtract(rect1, rect2);
      assert.equal(rects.length, 1);
      const rect = rects[0];
      assert.isTrue(Rect.equals(rect1, rect));
    });
  });

  should("have nothing when subtracting itself", () => {
    const rect = Rect.create(0, 0, 1, 1);
    const rects = Rect.subtract(rect, rect);
    assert.equal(rects.length, 0);
  });

  should("not overlap subtracted rect", () => {
    const rect = Rect.create(0, 0, 3, 3);
    for (let x = -2; x <= 2; x++) {
      for (let y = -2; y <= 2; y++) {
        for (let width = 1; width <= 3; width++) {
          for (let height = 1; height <= 3; height++) {
            const subtractRect = Rect.create(x, y, (x + width), (y + height));
            const resultRects = Rect.subtract(rect, subtractRect);
            for (let resultRect of resultRects) {
              assert.isFalse(Rect.intersects(subtractRect, resultRect));
            }
          }
        }
      }
    }
  });

  should("be contained in original rect", () => {
    const rect = Rect.create(0, 0, 3, 3);
    for (let x = -2; x <= 2; x++) {
      for (let y = -2; y <= 2; y++) {
        for (let width = 1; width <= 3; width++) {
          for (let height = 1; height <= 3; height++) {
            const subtractRect = Rect.create(x, y, (x + width), (y + height));
            const resultRects = Rect.subtract(rect, subtractRect);
            for (let resultRect of resultRects) {
              assert.isTrue(Rect.intersects(rect, resultRect));
            }
          }
        }
      }
    }
  });

  should("contain the subtracted rect in the original minus the results", () => {
    const rect = Rect.create(0, 0, 3, 3);
    for (let x = -2; x <= 2; x++) {
      for (let y = -2; y <= 2; y++) {
        for (let width = 1; width <= 3; width++) {
          for (let height = 1; height <= 3; height++) {
            const subtractRect = Rect.create(x, y, (x + width), (y + height));
            const resultRects = Rect.subtract(rect, subtractRect);
            let resultComplement = [Rect.copy(rect)];
            for (var resultRect of resultRects) {
              resultComplement = Array.prototype.concat.apply([],
                (resultComplement.map(rect => Rect.subtract(rect, resultRect))));
            }
            assert.isTrue(((resultComplement.length === 0) || (resultComplement.length === 1)));
            if (resultComplement.length === 1) {
              const complementRect = resultComplement[0];
              assert.isTrue(Rect.intersects(subtractRect, complementRect));
            }
          }
        }
      }
    }
  });
});

context("Rect overlaps", () => {
  should("detect that a rect overlaps itself", () => {
    const rect = Rect.create(2, 2, 4, 4);
    assert.isTrue(Rect.intersectsStrict(rect, rect));
  });

  should("detect that non-overlapping rectangles do not overlap on the left", () => {
    const rect1 = Rect.create(2, 2, 4, 4);
    const rect2 = Rect.create(0, 2, 1, 4);
    assert.isFalse(Rect.intersectsStrict(rect1, rect2));
  });

  should("detect that non-overlapping rectangles do not overlap on the right", () => {
    const rect1 = Rect.create(2, 2, 4, 4);
    const rect2 = Rect.create(5, 2, 6, 4);
    assert.isFalse(Rect.intersectsStrict(rect1, rect2));
  });

  should("detect that non-overlapping rectangles do not overlap on the top", () => {
    const rect1 = Rect.create(2, 2, 4, 4);
    const rect2 = Rect.create(2, 0, 2, 1);
    assert.isFalse(Rect.intersectsStrict(rect1, rect2));
  });

  should("detect that non-overlapping rectangles do not overlap on the bottom", () => {
    const rect1 = Rect.create(2, 2, 4, 4);
    const rect2 = Rect.create(2, 5, 2, 6);
    assert.isFalse(Rect.intersectsStrict(rect1, rect2));
  });

  should("detect overlapping rectangles on the left", () => {
    const rect1 = Rect.create(2, 2, 4, 4);
    const rect2 = Rect.create(0, 2, 2, 4);
    assert.isTrue(Rect.intersectsStrict(rect1, rect2));
  });

  should("detect overlapping rectangles on the right", () => {
    const rect1 = Rect.create(2, 2, 4, 4);
    const rect2 = Rect.create(4, 2, 5, 4);
    assert.isTrue(Rect.intersectsStrict(rect1, rect2));
  });

  should("detect overlapping rectangles on the top", () => {
    const rect1 = Rect.create(2, 2, 4, 4);
    const rect2 = Rect.create(2, 4, 4, 5);
    assert.isTrue(Rect.intersectsStrict(rect1, rect2));
  });

  should("detect overlapping rectangles on the bottom", () => {
    const rect1 = Rect.create(2, 2, 4, 4);
    const rect2 = Rect.create(2, 0, 4, 2);
    assert.isTrue(Rect.intersectsStrict(rect1, rect2));
  });

  should("detect overlapping rectangles when second rectangle is contained in first", () => {
    const rect1 = Rect.create(1, 1, 4, 4);
    const rect2 = Rect.create(2, 2, 3, 3);
    assert.isTrue(Rect.intersectsStrict(rect1, rect2));
  });

  should("detect overlapping rectangles when first rectangle is contained in second", () => {
    const rect1 = Rect.create(1, 1, 4, 4);
    const rect2 = Rect.create(2, 2, 3, 3);
    assert.isTrue(Rect.intersectsStrict(rect2, rect1));
  })
});
