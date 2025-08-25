package ace

import "core:math/fixed"

import "core:fmt"
aseData := #load("./tilemap.ase", []u8)

// SPEC: https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md

// data types

// BYTE: An 8-bit unsigned integer value
byte :: #type u8
// WORD: A 16-bit unsigned integer value
word :: #type u16le
// SHORT: A 16-bit signed integer value
short :: #type i16le
// DWORD: A 32-bit unsigned integer value
dword :: #type u32le
// LONG: A 32-bit signed integer value
long :: #type i32le
// FIXED: A 32-bit fixed point (16.16) value
fixed :: #type fixed.Fixed16_16
// FLOAT: A 32-bit single-precision value
float :: #type f32le
// DOUBLE: A 64-bit double-precision value
double :: #type f64le
// QWORD: A 64-bit unsigned integer value
qword :: #type u64le
// LONG64: A 64-bit signed integer value
long64 :: #type i64le
// POINT:
//     LONG: X coordinate value
//     LONG: Y coordinate value
point :: struct {
    x, y: long
}
// SIZE:
//     LONG: Width value
//     LONG: Height value
size :: struct {
    width, height: long
}
// RECT:
//     POINT: Origin coordinates
//     SIZE: Rectangle size
rect :: struct {
    origin: point,
    sz: size,
}
// PIXEL: One pixel, depending on the image pixel format:
//     RGBA: BYTE[4], each pixel have 4 bytes in this order Red, Green, Blue, Alpha.
//     Grayscale: BYTE[2], each pixel have 2 bytes in the order Value, Alpha.
//     Indexed: BYTE, each pixel uses 1 byte (the index).
// [TODO]

// TILE: Tilemaps: Each tile can be a 8-bit (BYTE), 16-bit (WORD), or 32-bit
// (DWORD) value and there are masks related to the meaning of each bit.
// [TODO]

// UUID: A Universally Unique Identifier stored as BYTE[16].
uuid :: #type [16]byte

// file structure

HEADER_MAGIC_NUMBER: u16le : 0xA5E0

AseFlags :: enum u32le {
    LayerOpacityValid               = 0,
    LayerBlendOpacityValidForGroups = 1,
    LayersHaveUUID                  = 2,
}
AseFlagsSet :: distinct bit_set[AseFlags;u32le]


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

AseFrameHeader :: struct #packed {
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

#assert(size_of(AseFrameHeader) == 16)

AseFrame :: struct {
    using header: AseFrameHeader,
}

AseChunkType :: enum u16le {
    OldPalette256 = 0x0004,
    OldPalette64  = 0x0011,
    Layer         = 0x2004,
    Cel           = 0x2005,
    CelExtra      = 0x2006,
    ColorProfile  = 0x2007,
    ExternalFiles = 0x2008,
    Mask          = 0x2016,
    Path          = 0x2017,
    Tags          = 0x2018,
    Palette       = 0x2019,
    UserData      = 0x2020,
    Slice         = 0x2022,
    Tileset       = 0x2023,
}

AseChunkHeader :: struct #packed {
    // DWORD       Chunk size
    size: u32le,
    // WORD        Chunk type
    type: AseChunkType,
}

AseChunkOldPalette256Packet :: struct #packed {
    // + For each packet
    //   BYTE      Number of palette entries to skip from the last packet (start from 0)
    skipCount:  u8,
    //   BYTE      Number of colors in the packet (0 means 256)
    colorCount: u8,
    //   + For each color in the packet
    //     BYTE    Red (0-255)
    red:        u8,
    //     BYTE    Green (0-255)
    green:      u8,
    //     BYTE    Blue (0-255)
    blue:       u8,
}

AseChunkOldPalette256 :: struct {
    // WORD        Number of packets
    packetCount: u16le,
    packets:     []AseChunkOldPalette256Packet,
}

AseChunkOldPalette64Packet :: struct #packed {
    // + For each packet
    //   BYTE      Number of palette entries to skip from the last packet (start from 0)
    skipCount:  u8,
    //   BYTE      Number of colors in the packet (0 means 256)
    colorCount: u8,
    //   + For each color in the packet
    //     BYTE    Red (0-255)
    red:        u8,
    //     BYTE    Green (0-255)
    green:      u8,
    //     BYTE    Blue (0-255)
    blue:       u8,
}

AseChunkOldPalette64 :: struct {
    // WORD        Number of packets
    packetCount: u16le,
    packets:     []AseChunkOldPalette64Packet,
}

AseChunkLayer :: struct {
    // WORD        Flags:
    //               1 = Visible
    //               2 = Editable
    //               4 = Lock movement
    //               8 = Background
    //               16 = Prefer linked cels
    //               32 = The layer group should be displayed collapsed
    //               64 = The layer is a reference layer
    // WORD        Layer type
    //               0 = Normal (image) layer
    //               1 = Group
    //               2 = Tilemap
    // WORD        Layer child level (see NOTE.1)
    // WORD        Default layer width in pixels (ignored)
    // WORD        Default layer height in pixels (ignored)
    // WORD        Blend mode (see NOTE.6)
    //               Normal         = 0
    //               Multiply       = 1
    //               Screen         = 2
    //               Overlay        = 3
    //               Darken         = 4
    //               Lighten        = 5
    //               Color Dodge    = 6
    //               Color Burn     = 7
    //               Hard Light     = 8
    //               Soft Light     = 9
    //               Difference     = 10
    //               Exclusion      = 11
    //               Hue            = 12
    //               Saturation     = 13
    //               Color          = 14
    //               Luminosity     = 15
    //               Addition       = 16
    //               Subtract       = 17
    //               Divide         = 18
    // BYTE        Opacity (see NOTE.6)
    // BYTE[3]     For future (set to zero)
    // STRING      Layer name
    // + If layer type = 2
    //   DWORD     Tileset index
    // + If file header flags have bit 4:
    //   UUID      Layer's universally unique identifier
}

AseChunkPayload :: union #no_nil {
    AseChunkOldPalette256,
    AseChunkOldPalette64,
}

AseChunk :: struct {
    using header: AseChunkHeader,
    payload:      AseChunkPayload,
}

#assert(size_of(AseChunkHeader) == 6)

main :: proc() {
    header := cast(^AseHeader)raw_data(aseData)
    assert(header.magicNumber == HEADER_MAGIC_NUMBER, message = "Invalid header magic number!")
    assert(header.fileSize == u32le(len(aseData)), "File size from the header doesn't match with the real file size")

    fmt.printfln("%#v", header)
}
