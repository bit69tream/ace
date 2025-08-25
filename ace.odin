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

HeaderFlags :: enum u32le {
    LayerOpacityValid               = 0,
    LayerBlendOpacityValidForGroups = 1,
    LayersHaveUUID                  = 2,
}
HeaderFlagsSet :: distinct bit_set[HeaderFlags;u32le]


Header :: struct #packed {
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
    flags:        HeaderFlagsSet,
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

#assert(size_of(Header) == 128)

FRAME_MAGIC_NUMBER: u16le : 0xF1FA

FrameHeader :: struct #packed {
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

#assert(size_of(FrameHeader) == 16)

Frame :: struct {
    using header: FrameHeader,
}

ChunkType :: enum u16le {
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

ChunkHeader :: struct #packed {
    // DWORD       Chunk size
    size: u32le,
    // WORD        Chunk type
    type: ChunkType,
}

ChunkOldPalette256Packet :: struct #packed {
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

ChunkOldPalette256 :: struct {
    // WORD        Number of packets
    packetCount: u16le,
    packets:     []ChunkOldPalette256Packet,
}

ChunkOldPalette64Packet :: struct #packed {
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

ChunkOldPalette64 :: struct {
    // WORD        Number of packets
    packetCount: u16le,
    packets:     []ChunkOldPalette64Packet,
}

LayerFlags :: enum u16le {
    // WORD        Flags:
    //               1 = Visible
    Visible             = 1,
    //               2 = Editable
    Editable            = 2,
    //               4 = Lock movement
    LockMovement        = 3,
    //               8 = Background
    Background          = 4,
    //               16 = Prefer linked cels
    PreferLinkedCels    = 5,
    //               32 = The layer group should be displayed collapsed
    LayerGroupCollapsed = 6,
    //               64 = The layer is a reference layer
    ReferenceLayer      = 7,
}
LayerFlagsSet :: distinct bit_set[LayerFlags;u16le]

LayerType :: enum u16le {
    // WORD        Layer type
    //               0 = Normal (image) layer
    Normal,
    //               1 = Group
    Group,
    //               2 = Tilemap
    Tilemap,
}

LayerBlendMode :: enum u16le {
    // WORD        Blend mode (see NOTE.6)
    //               Normal         = 0
    Normal     = 0,
    //               Multiply       = 1
    Multiply   = 1,
    //               Screen         = 2,
    Screen     = 2,
    //               Overlay        = 3
    Overlay    = 3,
    //               Darken         = 4
    Darken     = 4,
    //               Lighten        = 5
    Lighten    = 5,
    //               Color Dodge    = 6
    ColorDodge = 6,
    //               Color Burn     = 7
    ColorBurn  = 7,
    //               Hard Light     = 8
    HardLight  = 8,
    //               Soft Light     = 9
    SoftLight  = 9,
    //               Difference     = 10
    Difference = 10,
    //               Exclusion      = 11
    Exclusion  = 11,
    //               Hue            = 12
    Hue        = 12,
    //               Saturation     = 13
    Saturation = 13,
    //               Color          = 14
    Color      = 14,
    //               Luminosity     = 15
    Luminosity = 15,
    //               Addition       = 16
    Addition   = 16,
    //               Subtract       = 17
    Subtract   = 17,
    //               Divide         = 18
    Divide     = 18,
}

ChunkLayer :: struct {
    // WORD
    flags:        LayerFlagsSet,
    // WORD
    type:         LayerType,
    // WORD        Layer child level (see NOTE.1)
    childLevel:   u16le,
    // WORD        Default layer width in pixels (ignored)
    width:        u16le,
    // WORD        Default layer height in pixels (ignored)
    height:       u16le,
    // WORD
    blendMode:    LayerBlendMode,
    // BYTE        Opacity (see NOTE.6)
    opacity:      u8,
    // BYTE[3]     For future (set to zero)
    _:            [3]u8,
    // STRING      Layer name
    name:         string,
    // + If layer type = 2
    //   DWORD     Tileset index
    tilesetIndex: u32le,
    // + If file header flags have bit 4:
    //   UUID      Layer's universally unique identifier
    uuid:         [16]u8,
}

ChunkCel :: struct {
    // WORD        Layer index (see NOTE.2)
    index: u16le,
    // SHORT       X position
    // SHORT       Y position
    // BYTE        Opacity level
    // WORD        Cel Type
    //             0 - Raw Image Data (unused, compressed image is preferred)
    //             1 - Linked Cel
    //             2 - Compressed Image
    //             3 - Compressed Tilemap
    // SHORT       Z-Index (see NOTE.5)
    //             0 = default layer ordering
    //             +N = show this cel N layers later
    //             -N = show this cel N layers back
    // BYTE[5]     For future (set to zero)
    // + For cel type = 0 (Raw Image Data)
    //   WORD      Width in pixels
    //   WORD      Height in pixels
    //   PIXEL[]   Raw pixel data: row by row from top to bottom,
    //             for each scanline read pixels from left to right.
    // + For cel type = 1 (Linked Cel)
    //   WORD      Frame position to link with
    // + For cel type = 2 (Compressed Image)
    //   WORD      Width in pixels
    //   WORD      Height in pixels
    //   PIXEL[]   "Raw Cel" data compressed with ZLIB method (see NOTE.3)
    // + For cel type = 3 (Compressed Tilemap)
    //   WORD      Width in number of tiles
    //   WORD      Height in number of tiles
    //   WORD      Bits per tile (at the moment it's always 32-bit per tile)
    //   DWORD     Bitmask for tile ID (e.g. 0x1fffffff for 32-bit tiles)
    //   DWORD     Bitmask for X flip
    //   DWORD     Bitmask for Y flip
    //   DWORD     Bitmask for diagonal flip (swap X/Y axis)
    //   BYTE[10]  Reserved
    //   TILE[]    Row by row, from top to bottom tile by tile
    //             compressed with ZLIB method (see NOTE.3)
}

ChunkPayload :: union #no_nil {
    ChunkOldPalette256,
    ChunkOldPalette64,
    ChunkLayer,
    ChunkCel,
}

Chunk :: struct {
    using header: ChunkHeader,
    payload:      ChunkPayload,
}

#assert(size_of(ChunkHeader) == 6)

main :: proc() {
    header := cast(^Header)raw_data(aseData)
    assert(header.magicNumber == HEADER_MAGIC_NUMBER, message = "Invalid header magic number!")
    assert(header.fileSize == u32le(len(aseData)), "File size from the header doesn't match with the real file size")

    fmt.printfln("%#v", header)
}
