package test

import ".."
import "core:testing"
import "core:image"
import "core:image/png"

@(test)
wholeImage :: proc(t: ^testing.T) {
    f := ace.readFile("./test.ase")
    aseImg := ace.flatten(f)
    pngImg, err := png.load("./test.png", options = image.Options{.alpha_add_if_missing})
    assert(err == nil)

    testing.expect_value(t, aseImg.width, pngImg.width)
    testing.expect_value(t, aseImg.height, pngImg.height)
    testing.expect_value(t, aseImg.channels, pngImg.channels)
    testing.expect_value(t, aseImg.depth, pngImg.depth)

    testing.expect_value(t, len(aseImg.pixels.buf), len(pngImg.pixels.buf))

    for i in 0..<len(aseImg.pixels.buf) {
        testing.expect_value(t, aseImg.pixels.buf[i], pngImg.pixels.buf[i])
    }
}
