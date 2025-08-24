package ace

import "core:fmt"
aseData := #load("./tilemap.ase", []u8)

HEADER_MAGIC_NUMBER: u16le : 0xA5E0

AseFlags :: enum u32le {
    LayerOpacityValid               = 0,
    LayerBlendOpacityValidForGroups = 1,
    LayersHaveUUID                  = 2,
}
AseFlagsSet :: distinct bit_set[AseFlags;u32le]

// https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md#header
AseHeader :: struct #packed {
    // DWORD       File size
    fileSize:     u32le,
    // WORD        Magic number (0xA5E0)
    magicNumber:  u16le,
    // WORD        Frames
    frames:       u16le,
    // WORD        Width in pixels
    width:        u16le,
    // WORD        Height in pixels
    height:       u16le,
    // WORD        Color depth (bits per pixel)
    //               32 bpp = RGBA
    //               16 bpp = Grayscale
    //               8 bpp = Indexed
    colorDepth:   u16le,
    // DWORD       Flags (see NOTE.6):
    //               1 = Layer opacity has valid value
    //               2 = Layer blend mode/opacity is valid for groups
    //                   (composite groups separately first when rendering)
    //               4 = Layers have an UUID
    flags:        AseFlagsSet,
    // WORD        Speed (milliseconds between frame, like in FLC files)
    //             DEPRECATED: You should use the frame duration field
    //             from each frame header
    speed:        u16le,
    // DWORD       Set be 0
    _:            u32le,
    // DWORD       Set be 0
    _:            u32le,
    // BYTE        Palette entry (index) which represent transparent color
    //             in all non-background layers (only for Indexed sprites).
    paletteEntry: u8,
    // BYTE[3]     Ignore these bytes
    _:            [3]u8,
    // WORD        Number of colors (0 means 256 for old sprites)
    colorCount:   u16le,
    // BYTE        Pixel width (pixel ratio is "pixel width/pixel height").
    //             If this or pixel height field is zero, pixel ratio is 1:1
    pixelWidth:   u8,
    // BYTE        Pixel height
    pixelHeight:  u8,
    // SHORT       X position of the grid
    gridX:        i16le,
    // SHORT       Y position of the grid
    gridY:        i16le,
    // WORD        Grid width (zero if there is no grid, grid size
    //             is 16x16 on Aseprite by default)
    gridWidth:    u16le,
    // WORD        Grid height (zero if there is no grid)
    gridHeight:   u16le,
    // BYTE[84]    For future (set to zero)
    _:            [84]u8,
}

#assert(size_of(AseHeader) == 128)

FRAME_MAGIC_NUMBER: u16le : 0xF1FA

// https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md#frames
AseFrame :: struct #packed {
    // DWORD       Bytes in this frame
    bytes:         u32le,
    // WORD        Magic number (always 0xF1FA)
    magicNumber:   u16le,
    // WORD        Old field which specifies the number of "chunks"
    //             in this frame. If this value is 0xFFFF, we might
    //             have more chunks to read in this frame
    //             (so we have to use the new field)
    chunksOld:     u16le,
    // WORD        Frame duration (in milliseconds)
    frameDuration: u16le,
    // BYTE[2]     For future (set to zero)
    _:             [2]u8,
    // DWORD       New field which specifies the number of "chunks"
    //             in this frame (if this is 0, use the old field)
    chunksNew:     u32le,
}

#assert(size_of(AseFrame) == 16)

AseChunkHeader :: struct #packed {
    // DWORD       Chunk size
    size: u32le,
    // WORD        Chunk type
    type: u16le,
}

#assert(size_of(AseChunkHeader) == 6)

main :: proc() {
    header := cast(^AseHeader)raw_data(aseData)
    assert(header.magicNumber == HEADER_MAGIC_NUMBER, message = "Invalid header magic number!")
    assert(header.fileSize == u32le(len(aseData)), "File size from the header doesn't match with the real file size")

    fmt.printfln("%#v", header)
}
