package ace

import "core:fmt"
import "core:math/fixed"

@(rodata)
aseData := #load("./tilemap.ase", []u8)

// SPEC: https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md

// data types

// BYTE: An 8-bit unsigned integer value
Byte :: #type u8
// WORD: A 16-bit unsigned integer value
Word :: #type u16le
// SHORT: A 16-bit signed integer value
Short :: #type i16le
// DWORD: A 32-bit unsigned integer value
Dword :: #type u32le
// LONG: A 32-bit signed integer value
Long :: #type i32le
// FIXED: A 32-bit fixed point (16.16) value
Fixed :: #type fixed.Fixed16_16
// FLOAT: A 32-bit single-precision value
Float :: #type f32le
// DOUBLE: A 64-bit double-precision value
Double :: #type f64le
// QWORD: A 64-bit unsigned integer value
Qword :: #type u64le
// LONG64: A 64-bit signed integer value
Long64 :: #type i64le
// POINT:
//     LONG: X coordinate value
//     LONG: Y coordinate value
Point :: struct {
    x, y: Long,
}
// SIZE:
//     LONG: Width value
//     LONG: Height value
Size :: struct {
    width, height: Long,
}
// RECT:
//     POINT: Origin coordinates
//     SIZE: Rectangle size
Rect :: struct {
    origin: Point,
    size:   Size,
}
// PIXEL: One pixel, depending on the image pixel format:
//     RGBA: BYTE[4], each pixel have 4 bytes in this order Red, Green, Blue, Alpha.
//     Grayscale: BYTE[2], each pixel have 2 bytes in the order Value, Alpha.
//     Indexed: BYTE, each pixel uses 1 byte (the index).
// [TODO]
PixelRGBA :: struct {
    r, g, b, a: Byte,
}
PixelGrayscale :: struct {
    value, alpha: Byte,
}
PixelIndexed :: distinct Byte
Pixel :: union #no_nil {
    PixelRGBA,
    PixelGrayscale,
    PixelIndexed,
}

// TILE: Tilemaps: Each tile can be a 8-bit (BYTE), 16-bit (WORD), or 32-bit
// (DWORD) value and there are masks related to the meaning of each bit.
// Current spec states that at the moment TILE is always 32-bit, therefore i
// think it's fine to only support that size
// https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md#cel-chunk-0x2005
Tile :: #type Dword

// UUID: A Universally Unique Identifier stored as BYTE[16].
Uuid :: #type [16]Byte

// file structure

HEADER_MAGIC_NUMBER: Word : 0xA5E0

HeaderFlags :: enum Dword {
    LayerOpacityValid               = 0,
    LayerBlendOpacityValidForGroups = 1,
    LayersHaveUUID                  = 2,
}
HeaderFlagsSet :: distinct bit_set[HeaderFlags;Dword]


Header :: struct #packed {
    // DWORD       File size
    fileSize:     Dword,
    // WORD        Magic number (0xA5E0)
    magicNumber:  Word,
    // WORD        Frames
    frames:       Word,
    // WORD        Width in pixels
    width:        Word,
    // WORD        Height in pixels
    height:       Word,
    // WORD        Color depth (bits per pixel)
    //               32 bpp = RGBA
    //               16 bpp = Grayscale
    //               8 bpp = Indexed
    colorDepth:   Word,
    // DWORD       Flags (see NOTE.6):
    //               1 = Layer opacity has valid value
    //               2 = Layer blend mode/opacity is valid for groups
    //                   (composite groups separately first when rendering)
    //               4 = Layers have an UUID
    flags:        HeaderFlagsSet,
    // WORD        Speed (milliseconds between frame, like in FLC files)
    //             DEPRECATED: You should use the frame duration field
    //             from each frame header
    speed:        Word,
    // DWORD       Set be 0
    _:            Dword,
    // DWORD       Set be 0
    _:            Dword,
    // BYTE        Palette entry (index) which represent transparent color
    //             in all non-background layers (only for Indexed sprites).
    paletteEntry: Byte,
    // BYTE[3]     Ignore these bytes
    _:            [3]Byte,
    // WORD        Number of colors (0 means 256 for old sprites)
    colorCount:   Word,
    // BYTE        Pixel width (pixel ratio is "pixel width/pixel height").
    //             If this or pixel height field is zero, pixel ratio is 1:1
    pixelWidth:   Byte,
    // BYTE        Pixel height
    pixelHeight:  Byte,
    // SHORT       X position of the grid
    gridX:        Short,
    // SHORT       Y position of the grid
    gridY:        Short,
    // WORD        Grid width (zero if there is no grid, grid size
    //             is 16x16 on Aseprite by default)
    gridWidth:    Word,
    // WORD        Grid height (zero if there is no grid)
    gridHeight:   Word,
    // BYTE[84]    For future (set to zero)
    _:            [84]Byte,
}

#assert(size_of(Header) == 128)

FRAME_MAGIC_NUMBER: Word : 0xF1FA

FrameHeader :: struct #packed {
    // DWORD       Bytes in this frame
    byteCount:     Dword,
    // WORD        Magic number (always 0xF1FA)
    magicNumber:   Word,
    // WORD        Old field which specifies the number of "chunks"
    //             in this frame. If this value is 0xFFFF, we might
    //             have more chunks to read in this frame
    //             (so we have to use the new field)
    chunksOld:     Word,
    // WORD        Frame duration (in milliseconds)
    frameDuration: Word,
    // BYTE[2]     For future (set to zero)
    _:             [2]Byte,
    // DWORD       New field which specifies the number of "chunks"
    //             in this frame (if this is 0, use the old field)
    chunksNew:     Dword,
}

#assert(size_of(FrameHeader) == 16)

Frame :: struct {
    using header: FrameHeader,
    chunks:       []Chunk,
}

ChunkType :: enum Word {
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
    size: Dword,
    // WORD        Chunk type
    type: ChunkType,
}

ChunkOldPalettePacket :: struct #packed {
    // + For each packet
    //   BYTE      Number of palette entries to skip from the last packet (start from 0)
    skipCount:  Byte,
    //   BYTE      Number of colors in the packet (0 means 256 (or 64))
    colorCount: Byte,
    //   + For each color in the packet
    //     BYTE    Red (0-255 (or 63))
    red:        Byte,
    //     BYTE    Green (0-255 (or 63))
    green:      Byte,
    //     BYTE    Blue (0-255 (or 63))
    blue:       Byte,
}

ChunkOldPalette256 :: struct {
    // WORD        Number of packets
    packetCount: Word,
    packets:     []ChunkOldPalettePacket,
}

ChunkOldPalette64 :: struct {
    // WORD        Number of packets
    packetCount: Word,
    packets:     []ChunkOldPalettePacket,
}

LayerFlags :: enum Word {
    // WORD        Flags:
    //               1 = Visible
    Visible             = 0,
    //               2 = Editable
    Editable            = 1,
    //               4 = Lock movement
    LockMovement        = 2,
    //               8 = Background
    Background          = 3,
    //               16 = Prefer linked cels
    PreferLinkedCels    = 4,
    //               32 = The layer group should be displayed collapsed
    LayerGroupCollapsed = 5,
    //               64 = The layer is a reference layer
    ReferenceLayer      = 6,
}
LayerFlagsSet :: distinct bit_set[LayerFlags;Word]

LayerType :: enum Word {
    // WORD        Layer type
    //               0 = Normal (image) layer
    Normal,
    //               1 = Group
    Group,
    //               2 = Tilemap
    Tilemap,
}

LayerBlendMode :: enum Word {
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
    childLevel:   Word,
    // WORD        Default layer width in pixels (ignored)
    width:        Word,
    // WORD        Default layer height in pixels (ignored)
    height:       Word,
    // WORD
    blendMode:    LayerBlendMode,
    // BYTE        Opacity (see NOTE.6)
    opacity:      Byte,
    // BYTE[3]     For future (set to zero)
    _:            [3]Byte,
    // STRING      Layer name
    name:         string,
    // + If layer type = 2
    //   DWORD     Tileset index
    tilesetIndex: Dword,
    // + If file header flags have bit 4:
    //   UUID      Layer's universally unique identifier
    uuid:         Uuid,
}

ChunkCelType :: enum Word {
    // WORD        Cel Type
    //             0 - Raw Image Data (unused, compressed image is preferred)
    Raw               = 0,
    //             1 - Linked Cel
    Linked            = 1,
    //             2 - Compressed Image
    CompressedImage   = 2,
    //             3 - Compressed Tilemap
    CompressedTilemap = 3,
}

ChunkCelPayloadRaw :: struct {
    // + For cel type = 0 (Raw Image Data)
    //   WORD      Width in pixels
    width:  Word,
    //   WORD      Height in pixels
    height: Word,
    //   PIXEL[]   Raw pixel data: row by row from top to bottom,
    //             for each scanline read pixels from left to right.
    data:   []Pixel,
}

ChunkCelPayloadLinked :: struct {
    // + For cel type = 1 (Linked Cel)
    //   WORD      Frame position to link with
    framePosition: Word,
}

ChunkCelPayloadCompressedImage :: struct {
    // + For cel type = 2 (Compressed Image)
    //   WORD      Width in pixels
    width:  Word,
    //   WORD      Height in pixels
    height: Word,
    //   PIXEL[]   "Raw Cel" data compressed with ZLIB method (see NOTE.3)
    data:   []Pixel,
}

ChunkCelPayloadCompressedTilemap :: struct {
    // + For cel type = 3 (Compressed Tilemap)
    //   WORD      Width in number of tiles
    width:               Word,
    //   WORD      Height in number of tiles
    height:              Word,
    //   WORD      Bits per tile (at the moment it's always 32-bit per tile)
    bitsPerTile:         Word,
    //   DWORD     Bitmask for tile ID (e.g. 0x1fffffff for 32-bit tiles)
    tileIDBitmask:       Dword,
    //   DWORD     Bitmask for X flip
    xFlipBitmask:        Dword,
    //   DWORD     Bitmask for Y flip
    yFlipBitmask:        Dword,
    //   DWORD     Bitmask for diagonal flip (swap X/Y axis)
    diagonalFlipBitmask: Dword,
    //   BYTE[10]  Reserved
    _:                   [10]Byte,
    //   TILE[]    Row by row, from top to bottom tile by tile
    //             compressed with ZLIB method (see NOTE.3)
    data:                []Tile,
}

ChunkCelPayload :: union #no_nil {
    ChunkCelPayloadRaw,
    ChunkCelPayloadLinked,
    ChunkCelPayloadCompressedImage,
    ChunkCelPayloadCompressedTilemap,
}

ChunkCel :: struct {
    // WORD        Layer index (see NOTE.2)
    index:   Word,
    // SHORT       X position
    x:       Short,
    // SHORT       Y position
    y:       Short,
    // BYTE        Opacity level
    opacity: Byte,
    // WORD
    type:    ChunkCelType,
    // SHORT       Z-Index (see NOTE.5)
    //             0 = default layer ordering
    //             +N = show this cel N layers later
    //             -N = show this cel N layers back
    z:       Short,
    // BYTE[5]     For future (set to zero)
    _:       [5]Byte,
    payload: ChunkCelPayload,
}

ChunkCelExtraFlags :: enum Dword {
    // DWORD       Flags (set to zero)
    //               1 = Precise bounds are set
    PreciseBound = 1,
}

ChunkCelExtra :: struct {
    flags:  ChunkCelExtraFlags,
    // FIXED       Precise X position
    x:      Fixed,
    // FIXED       Precise Y position
    y:      Fixed,
    // FIXED       Width of the cel in the sprite (scaled in real-time)
    width:  Fixed,
    // FIXED       Height of the cel in the sprite
    height: Fixed,
    // BYTE[16]    For future use (set to zero)
    _:      [16]Byte,
}

ChunkColorProfileType :: enum Word {
    // WORD        Type
    //               0 - no color profile (as in old .aseprite files)
    NoProfile   = 0,
    //               1 - use sRGB
    sRGB        = 1,
    //               2 - use the embedded ICC profile
    EmbeddedICC = 2,
}

ChunkColorProfileFlags :: enum Word {
    // WORD        Flags
    //               1 - use special fixed gamma
    UseFixedGamma = 1,
}

ChunkColorProfile :: struct #packed {
    // WORD
    type:  ChunkColorProfileType,
    // WORD
    flags: ChunkColorProfileFlags,
    // FIXED       Fixed gamma (1.0 = linear)
    //             Note: The gamma in sRGB is 2.2 in overall but it doesn't use
    //             this fixed gamma, because sRGB uses different gamma sections
    //             (linear and non-linear). If sRGB is specified with a fixed
    //             gamma = 1.0, it means that this is Linear sRGB.
    gamma: Fixed,
    // BYTE[8]     Reserved (set to zero)
    _:     [8]Byte,

    // [TODO]: ICC is unsupported
    // + If type = ICC:
    //   DWORD     ICC profile data length
    //   BYTE[]    ICC profile data. More info: http://www.color.org/ICC1V42.pdf
}

ChunkPaletteEntryFlags :: enum Word {
    //   WORD      Entry flags:
    //               1 = Has name
    HasName = 1,
}

ChunkPaletteEntry :: struct #packed {
    // + For each palette entry in [from,to] range (to-from+1 entries)
    flags: ChunkPaletteEntryFlags,
    //   BYTE      Red (0-255)
    r:     Byte,
    //   BYTE      Green (0-255)
    g:     Byte,
    //   BYTE      Blue (0-255)
    b:     Byte,
    //   BYTE      Alpha (0-255)
    a:     Byte,
    //   + If has name bit in entry flags
    //     STRING  Color name
    name:  string,
}

ChunkPalette :: struct #packed {
    // DWORD       New palette size (total number of entries)
    length:     Dword,
    // DWORD       First color index to change
    firstIndex: Dword,
    // DWORD       Last color index to change
    lastIndex:  Dword,
    // BYTE[8]     For future (set to zero)
    _:          [8]Byte,
    entries:    []ChunkPaletteEntry,
}

ChunkPayload :: union #no_nil {
    ChunkOldPalette256,
    ChunkOldPalette64,
    ChunkLayer,
    ChunkCel,
    ChunkCelExtra,
    ChunkColorProfile,
    ChunkPalette,
}

Chunk :: struct {
    using header: ChunkHeader,
    payload:      ChunkPayload,
}

#assert(size_of(ChunkHeader) == 6)

readHeader :: proc(data: []u8) -> (out: Header, advance: uintptr) {
    out = (cast(^Header)raw_data(data))^
    assert(out.magicNumber == HEADER_MAGIC_NUMBER, message = "Invalid header magic number!")
    advance = size_of(Header)

    assert(.LayersHaveUUID in out.flags, message = "Layers with UUID are not currently supported")

    return
}

readFrame :: proc(data: []u8) -> (out: Frame, advance: uintptr) {
    out.header = (cast(^FrameHeader)raw_data(data))^
    assert(out.header.magicNumber == FRAME_MAGIC_NUMBER, message = "Invalid frame magic number!")
    advance = size_of(FrameHeader)

    chunkCount := u32(out.header.chunksNew)
    if chunkCount == 0 do chunkCount = u32(out.header.chunksOld)
    out.chunks = make([]Chunk, chunkCount)

    for i in 0 ..< chunkCount {
        chunk, offset := readChunk(data[advance:])
        out.chunks[i] = chunk
        advance += offset
    }

    return
}

readChunkColorProfile :: proc(data: []u8) -> (out: ChunkColorProfile) {
    out = (cast(^ChunkColorProfile)raw_data(data))^
    assert(out.type != .EmbeddedICC, "Embedded ICC profiles are not supported")

    return
}

readString :: proc(data: []u8) -> (out: string) {
    length := uintptr((cast(^Word)raw_data(data))^)
    out = string(data[2:length + 2])

    return
}

readChunkPalette :: proc(data: []u8) -> (out: ChunkPalette) {
    out = (cast(^ChunkPalette)raw_data(data))^
    out.entries = make([]ChunkPaletteEntry, out.length)

    readPaletteEntry :: proc(data: []u8) -> (out: ChunkPaletteEntry, advance: uintptr) {
        nameOffset :: offset_of(ChunkPaletteEntry, name)
        out = (cast(^ChunkPaletteEntry)raw_data(data))^
        if out.flags == .HasName {
            out.name = readString(data[nameOffset:])
        } else {
            out.name = ""
        }

        return
    }

    offset: uintptr = offset_of(ChunkPalette, entries)
    for i in 0 ..< out.length {
        entry, advance := readPaletteEntry(data[offset:])
        out.entries[i] = entry
        offset += advance
    }

    return
}

readChunkLayer :: proc(data: []u8) -> (out: ChunkLayer) {
    offset: uintptr = 0

    out.flags = (cast(^LayerFlagsSet)raw_data(data[offset:]))^;offset += size_of(LayerFlagsSet)
    out.type = (cast(^LayerType)raw_data(data[offset:]))^;offset += size_of(LayerType)
    out.childLevel = (cast(^Word)raw_data(data[offset:]))^;offset += size_of(Word)
    out.width = (cast(^Word)raw_data(data[offset:]))^;offset += size_of(Word)
    out.height = (cast(^Word)raw_data(data[offset:]))^;offset += size_of(Word)
    out.blendMode = (cast(^LayerBlendMode)raw_data(data[offset:]))^;offset += size_of(LayerBlendMode)
    out.opacity = (cast(^Byte)raw_data(data[offset:]))^;offset += size_of(Byte)
    offset += size_of(Byte)*3
    out.name = readString(data[offset:]); offset += uintptr(len(out.name))

    if out.type == .Tilemap {
        out.tilesetIndex = (cast(^Dword)raw_data(data[offset:]))^;offset += size_of(Dword)
    }

    // [TODO]: UUID for layers
    // UUID only exists if .LayersHaveUUID flag is set in the file header. To
    // parse it here we need to pass some kind of context

    return
}

readChunk :: proc(data: []u8) -> (out: Chunk, advance: uintptr) {
    out.header = (cast(^ChunkHeader)raw_data(data))^
    advance = uintptr(out.header.size)

    payloadOffset := size_of(ChunkHeader)
    payloadData := data[payloadOffset:]
    switch out.header.type {
    case .OldPalette256:
        assert(false, "[TODO]: OldPalette256 chunk not supported")
    case .OldPalette64:
        assert(false, "[TODO]: OldPalette64 chunk not supported")
    case .Layer:
        out.payload = readChunkLayer(payloadData)
    case .Cel:
        assert(false, "[TODO]: Cel chunk not supported")
    case .CelExtra:
        assert(false, "[TODO]: CelExtra chunk not supported")
    case .ColorProfile:
        out.payload = readChunkColorProfile(payloadData)
    case .ExternalFiles:
        assert(false, "[TODO]: ExternalFiles chunk not supported")
    case .Mask:
        assert(false, "[TODO]: Mask chunk not supported")
    case .Path:
        assert(false, "[TODO]: Path chunk not supported")
    case .Tags:
        assert(false, "[TODO]: Tags chunk not supported")
    case .Palette:
        out.payload = readChunkPalette(payloadData)
    case .UserData:
        assert(false, "[TODO]: UserData chunk not supported")
    case .Slice:
        assert(false, "[TODO]: Slice chunk not supported")
    case .Tileset:
        assert(false, "[TODO]: Tileset chunk not supported")
    }
    fmt.printfln("%#v", out)

    return
}

main :: proc() {
    pointer: uintptr = 0
    header, offset := readHeader(aseData)
    assert(header.fileSize == u32le(len(aseData)), "File size from the header doesn't match with the real file size")
    pointer += offset

    frame: Frame
    frame, offset = readFrame(aseData[pointer:])
    pointer += offset

    fmt.printfln("%#v", header)
    fmt.printfln("%#v", frame)
}
