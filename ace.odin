package ace

import "core:bytes"
import "core:compress/zlib"
import "core:fmt"
import "core:math/fixed"

@(rodata)
aseData := #load("./tilemap.ase", []u8)

Ctx :: struct {
    colorDepth:     ColorDepth,
    layersHaveUUID: bool,
}

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
PixelRGBA :: struct #packed {
    r, g, b, a: Byte,
}
PixelGrayscale :: struct #packed {
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
Tile :: distinct Dword

// UUID: A Universally Unique Identifier stored as BYTE[16].
Uuid :: distinct [16]Byte

// file structure

HEADER_MAGIC_NUMBER: Word : 0xA5E0

HeaderFlags :: enum Dword {
    LayerOpacityValid               = 0,
    LayerBlendOpacityValidForGroups = 1,
    LayersHaveUUID                  = 2,
}
HeaderFlagsSet :: distinct bit_set[HeaderFlags;Dword]

ColorDepth :: enum Word {
    Indexed   = 8,
    Grayscale = 16,
    RGBA      = 32,
}

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
    colorDepth:   ColorDepth,
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
    Normal  = 0,
    //               1 = Group
    Group   = 1,
    //               2 = Tilemap
    Tilemap = 2,
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
ChunkCelExtraFlagsSet :: bit_set[ChunkCelExtraFlags;Dword]

ChunkCelExtra :: struct {
    flags:  ChunkCelExtraFlagsSet,
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
ChunkColorProfileFlagsSet :: bit_set[ChunkColorProfileFlags;Word]

ChunkColorProfile :: struct #packed {
    // WORD
    type:  ChunkColorProfileType,
    // WORD
    flags: ChunkColorProfileFlagsSet,
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
ChunkPaletteEntryFlagsSet :: bit_set[ChunkPaletteEntryFlags;Word]

ChunkPaletteEntry :: struct #packed {
    // + For each palette entry in [from,to] range (to-from+1 entries)
    flags: ChunkPaletteEntryFlagsSet,
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

ChunkSliceFlags :: enum Dword {
    // DWORD       Flags
    //               1 = It's a 9-patches slice
    NinePatches = 0,
    //               2 = Has pivot information
    HasPivot    = 1,
}
ChunkSliceFlagsSet :: bit_set[ChunkSliceFlags;Dword]

ChunkSliceKey :: struct {
    // + For each slice key
    //   DWORD     Frame number (this slice is valid from
    //             this frame to the end of the animation)
    frameNumber:  Dword,
    //   LONG      Slice X origin coordinate in the sprite
    xOrigin:      Long,
    //   LONG      Slice Y origin coordinate in the sprite
    yOrigin:      Long,
    //   DWORD     Slice width (can be 0 if this slice hidden in the
    //             animation from the given frame)
    width:        Dword,
    //   DWORD     Slice height
    height:       Dword,
    //   + If flags have bit 1
    //     LONG    Center X position (relative to slice bounds)
    centerX:      Long,
    //     LONG    Center Y position
    centerY:      Long,
    //     DWORD   Center width
    centerWidth:  Dword,
    //     DWORD   Center height
    centerHeight: Dword,
    //   + If flags have bit 2
    //     LONG    Pivot X position (relative to the slice origin)
    pivotX:       Long,
    //     LONG    Pivot Y position (relative to the slice origin)
    pivotY:       Long,
}

ChunkSlice :: struct {
    // DWORD       Number of "slice keys"
    keyCount: Dword,
    // DWORD
    flags:    ChunkSliceFlagsSet,
    // DWORD       Reserved
    _:        Dword,
    // STRING      Name
    name:     string,
    keys:     []ChunkSliceKey,
}

ChunkUserDataFlags :: enum Dword {
    // DWORD       Flags
    //               1 = Has text
    HasText       = 0,
    //               2 = Has color
    HasColor      = 1,
    //               4 = Has properties
    HasProperties = 2,
}
ChunkUserDataFlagsSet :: bit_set[ChunkUserDataFlags;Dword]

ChunkUserDataPropertyType :: enum Word {
    //       + If type==0x0001 (bool)
    //         BYTE    == 0 means FALSE
    //                 != 0 means TRUE
    Bool         = 0x0001,
    //       + If type==0x0002 (int8)
    //         BYTE
    SignedByte   = 0x0002,
    //       + If type==0x0003 (uint8)
    //         BYTE
    UnsignedByte = 0x0003,
    //       + If type==0x0004 (int16)
    //         SHORT
    Short        = 0x0004,
    //       + If type==0x0005 (uint16)
    //         WORD
    Word         = 0x0005,
    //       + If type==0x0006 (int32)
    //         LONG
    Long         = 0x0006,
    //       + If type==0x0007 (uint32)
    //         DWORD
    Dword        = 0x0007,
    //       + If type==0x0008 (int64)
    //         LONG64
    Long64       = 0x0008,
    //       + If type==0x0009 (uint64)
    //         QWORD
    Qword        = 0x0009,
    //       + If type==0x000A
    //         FIXED
    Fixed        = 0x000A,
    //       + If type==0x000B
    //         FLOAT
    Float        = 0x000B,
    //       + If type==0x000C
    //         DOUBLE
    Double       = 0x000C,
    //       + If type==0x000D
    //         STRING
    String       = 0x000D,
    //       + If type==0x000E
    //         POINT
    Point        = 0x000E,
    //       + If type==0x000F
    //         SIZE
    Size         = 0x000F,
    //       + If type==0x0010
    //         RECT
    Rect         = 0x0010,
    //       + If type==0x0011 (vector)
    Vector       = 0x0011,
    //       + If type==0x0012 (nested properties map)
    //         DWORD     Number of properties
    //         BYTE[]    Nested properties data
    //                   Structure is the same as indicated in this loop
    Nested       = 0x0012,
    //       + If type==0x0013
    //         UUID
    UUID         = 0x0013,
}

ChunkUserDataVectorElementTagged :: struct {
    type:  ChunkUserDataVectorElementType,
    value: []Byte,
}

ChunkUserDataVectorElementSimple :: #type []Byte

ChunkUserDataVectorElement :: union #no_nil {
    // + If Element's type == 0 (all elements are not of the same type)
    //   For each element:
    //     WORD      Element's type
    //     BYTE[]    Element's value. Structure depends on the
    //               element's type
    // + Else (all elements are of the same type)
    //   For each element:
    //     BYTE[]    Element's value. Structure depends on the
    //               element's type
    ChunkUserDataVectorElementTagged,
    ChunkUserDataVectorElementSimple,
}

ChunkUserDataVector :: struct {
    //         DWORD     Number of elements
    length:      Dword,
    //         WORD      Element's type.
    elementType: ChunkUserDataVectorElementType,
    elements:    []ChunkUserDataVectorElement,
}

ChunkUserDataVectorElementType :: #type ChunkUserDataPropertyType

ChunkUserDataPropertyPayload :: union #no_nil {
    bool,
    i8,
    u8,
    Short,
    Word,
    Long,
    Dword,
    Long64,
    Qword,
    Fixed,
    Float,
    Double,
    string,
    Point,
    Size,
    Rect,
    ChunkUserDataVector,
    ChunkUserDataProperties,
    Uuid,
}

ChunkUserDataProperty :: struct {
    name:  string,
    type:  ChunkUserDataPropertyType,
    value: ChunkUserDataPropertyPayload,
}

ChunkUserDataProperties :: struct {
    //     DWORD     Number of properties
    propertyCount: Dword,
    //     + For each property:
    //       STRING    Name
    //       WORD      Type
    properties:    []ChunkUserDataProperty,
}

ChunkUserDataPropertyMap :: struct {
    //   + For each properties map:
    //     DWORD     Properties maps key
    //               == 0 means user properties
    //               != 0 means an extension Entry ID (see External Files Chunk))
    key:           Dword,
    using payload: ChunkUserDataProperties,
}

ChunkUserData :: struct {
    flags:                 ChunkUserDataFlagsSet,
    // + If flags have bit 1
    //   STRING    Text
    text:                  string,
    // + If flags have bit 2
    //   BYTE      Color Red (0-255)
    //   BYTE      Color Green (0-255)
    //   BYTE      Color Blue (0-255)
    //   BYTE      Color Alpha (0-255)
    r, g, b, a:            Byte,
    // + If flags have bit 4
    //   DWORD     Size in bytes of all properties maps stored in this chunk
    //             The size includes the this field and the number of property maps
    //             (so it will be a value greater or equal to 8 bytes).
    propertiesPayloadSize: Dword,
    //   DWORD     Number of properties maps
    propertyMapsCount:     Dword,
    propertyMaps:          []ChunkUserDataPropertyMap,
}

ChunkPayload :: union #no_nil {
    ChunkOldPalette256,
    ChunkOldPalette64,
    ChunkLayer,
    ChunkCel,
    ChunkCelExtra,
    ChunkColorProfile,
    ChunkPalette,
    ChunkSlice,
    ChunkUserData,
}

Chunk :: struct {
    using header: ChunkHeader,
    payload:      ChunkPayload,
}

#assert(size_of(ChunkHeader) == 6)

readHeader :: proc(data: []u8) -> (out: Header, advance: uintptr) {
    out = dataAs(data, Header)
    assert(out.magicNumber == HEADER_MAGIC_NUMBER, message = "Invalid header magic number!")
    advance = size_of(Header)

    return
}

readFrame :: proc(data: []u8) -> (out: Frame, advance: uintptr) {
    out.header = dataAs(data, FrameHeader)
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
    out = dataAs(data, ChunkColorProfile)
    assert(out.type != .EmbeddedICC, "Embedded ICC profiles are not supported")

    return
}

readString :: proc(data: []u8) -> (out: string) {
    length := uintptr(dataAs(data, Word))
    out = string(data[2:length + 2])

    return
}

readChunkPalette :: proc(data: []u8) -> (out: ChunkPalette) {
    offset := uintptr(0)
    out.length = dataAs(data[offset:], Dword); offset += size_of(Dword)
    out.firstIndex = dataAs(data[offset:], Dword); offset += size_of(Dword)
    out.lastIndex = dataAs(data[offset:], Dword); offset += size_of(Dword)
    offset += 8

    readChunkPaletteEntry :: proc (data: []u8) -> (out: ChunkPaletteEntry, advance: uintptr) {
        offset := uintptr(0)

        out.flags = dataAs(data[offset:], ChunkPaletteEntryFlagsSet); offset += size_of(ChunkPaletteEntryFlagsSet)
        out.r = dataAs(data[offset:], Byte); offset += size_of(Byte)
        out.g = dataAs(data[offset:], Byte); offset += size_of(Byte)
        out.b = dataAs(data[offset:], Byte); offset += size_of(Byte)
        out.a = dataAs(data[offset:], Byte); offset += size_of(Byte)

        if .HasName in out.flags {
            out.name = readString(data[offset:]); offset += stringOffset(out.name)
        }

        advance = offset

        return
    }

    out.entries = make([]ChunkPaletteEntry, out.length)
    for i in 0..<out.length {
        entry, advance := readChunkPaletteEntry(data[offset:])
        out.entries[i] = entry
        offset += advance
    }

    return
}

dataAs :: #force_inline proc(data: []u8, $T: typeid) -> T {
    return (cast(^T)raw_data(data))^
}

stringOffset :: proc(s: string) -> uintptr {
    return uintptr(len(s) + size_of(Word))
}

readChunkLayer :: proc(data: []u8) -> (out: ChunkLayer) {
    offset: uintptr = 0

    out.flags = dataAs(data[offset:], LayerFlagsSet);offset += size_of(LayerFlagsSet)
    out.type = dataAs(data[offset:], LayerType);offset += size_of(LayerType)
    out.childLevel = dataAs(data[offset:], Word);offset += size_of(Word)
    out.width = dataAs(data[offset:], Word);offset += size_of(Word)
    out.height = dataAs(data[offset:], Word);offset += size_of(Word)
    out.blendMode = dataAs(data[offset:], LayerBlendMode);offset += size_of(LayerBlendMode)
    out.opacity = dataAs(data[offset:], Byte);offset += size_of(Byte)
    offset += size_of(Byte) * 3
    out.name = readString(data[offset:]);offset += stringOffset(out.name)

    if out.type == .Tilemap {
        out.tilesetIndex = dataAs(data[offset:], Dword);offset += size_of(Dword)
    }

    ctx := (cast(^Ctx)context.user_ptr)^
    if ctx.layersHaveUUID {
        out.uuid = dataAs(data[offset:], Uuid)
    }

    return
}

readChunkSlice :: proc(data: []u8) -> (out: ChunkSlice) {
    offset: uintptr = 0

    out.keyCount = dataAs(data[offset:], Dword);offset += size_of(Dword)
    out.flags = dataAs(data[offset:], ChunkSliceFlagsSet);offset += size_of(ChunkSliceFlagsSet)
    offset += size_of(Dword)
    out.name = readString(data[offset:]);offset += stringOffset(out.name)

    out.keys = make([]ChunkSliceKey, out.keyCount)
    for i in 0 ..< out.keyCount {
        out.keys[i].frameNumber = dataAs(data[offset:], Dword);offset += size_of(Dword)
        out.keys[i].xOrigin = dataAs(data[offset:], Long);offset += size_of(Long)
        out.keys[i].yOrigin = dataAs(data[offset:], Long);offset += size_of(Long)
        out.keys[i].width = dataAs(data[offset:], Dword);offset += size_of(Dword)
        out.keys[i].height = dataAs(data[offset:], Dword);offset += size_of(Dword)

        if .NinePatches in out.flags {
            out.keys[i].centerX = dataAs(data[offset:], Long);offset += size_of(Long)
            out.keys[i].centerY = dataAs(data[offset:], Long);offset += size_of(Long)
            out.keys[i].centerWidth = dataAs(data[offset:], Dword);offset += size_of(Dword)
            out.keys[i].centerHeight = dataAs(data[offset:], Dword);offset += size_of(Dword)
        }

        if .HasPivot in out.flags {
            out.keys[i].pivotX = dataAs(data[offset:], Long);offset += size_of(Long)
            out.keys[i].pivotY = dataAs(data[offset:], Long);offset += size_of(Long)
        }
    }

    return
}

readChunkUserData :: proc(data: []u8) -> (out: ChunkUserData) {
    offset := uintptr(0)
    out.flags = dataAs(data[offset:], ChunkUserDataFlagsSet);offset += size_of(ChunkUserDataFlagsSet)

    if .HasText in out.flags {
        out.text = readString(data[offset:]);offset += stringOffset(out.text)
    }

    if .HasColor in out.flags {
        out.r = data[offset];offset += size_of(Byte)
        out.g = data[offset];offset += size_of(Byte)
        out.b = data[offset];offset += size_of(Byte)
        out.a = data[offset];offset += size_of(Byte)
    }

    if .HasProperties in out.flags {
        out.propertiesPayloadSize = dataAs(data[offset:], Dword);offset += size_of(Dword)
        out.propertyMapsCount = dataAs(data[offset:], Dword);offset += size_of(Dword)

        panic("Property maps are not supported yet")
    }

    return
}

readCompressedImage :: proc(data: []u8) -> (img: ChunkCelPayloadCompressedImage) {
    offset := uintptr(0)

    img.width = dataAs(data[offset:], Word);offset += size_of(Word)
    img.height = dataAs(data[offset:], Word);offset += size_of(Word)
    img.data = make([]Pixel, img.width * img.height)

    buf: bytes.Buffer
    err := zlib.inflate(data[offset:], &buf)
    defer bytes.buffer_destroy(&buf)

    if err != nil {
        fmt.printfln("Cannot inflate image data: %v", err)
        panic("")
    }

    assert(len(buf.buf) == int(img.width * img.height))

    ctx := (cast(^Ctx)context.user_ptr)^

    d := data[offset:]
    switch ctx.colorDepth {
    case .Indexed:
        for i in 0 ..< (img.width * img.height) {
            img.data[i] = PixelIndexed(buf.buf[i])
        }
    case .Grayscale:
        for i in 0 ..< (img.width * img.height) {
            img.data[i] = dataAs(buf.buf[i * size_of(PixelGrayscale):], PixelGrayscale)
        }
    case .RGBA:
        for i in 0 ..< (img.width * img.height) {
            img.data[i] = dataAs(buf.buf[i * size_of(PixelRGBA):], PixelRGBA)
        }
    }

    return
}

readChunkCel :: proc(data: []u8) -> (out: ChunkCel) {
    offset := uintptr(0)
    out.index = dataAs(data[offset:], Word);offset += size_of(Word)
    out.x = dataAs(data[offset:], Short);offset += size_of(Short)
    out.y = dataAs(data[offset:], Short);offset += size_of(Short)
    out.opacity = dataAs(data[offset:], Byte);offset += size_of(Byte)
    out.type = dataAs(data[offset:], ChunkCelType);offset += size_of(ChunkCelType)
    out.z = dataAs(data[offset:], Short);offset += size_of(Short)
    offset += 5

    switch out.type {
    case .Raw:
        panic("Raw Cel chunks are not supported")
    case .Linked:
        panic("Linked Cel chunks are not supported")
    case .CompressedImage:
        out.payload = readCompressedImage(data[offset:])
    case .CompressedTilemap:
        panic("Compressed tilemap Cel chunks are not supported")
    }

    return
}

readChunk :: proc(data: []u8) -> (out: Chunk, advance: uintptr) {
    out.header = dataAs(data, ChunkHeader)
    advance = uintptr(out.header.size)

    payloadOffset := size_of(ChunkHeader)
    payloadData := data[payloadOffset:advance]
    switch out.header.type {
    case .OldPalette256:
        assert(false, "[TODO]: OldPalette256 chunk not supported")
    case .OldPalette64:
        assert(false, "[TODO]: OldPalette64 chunk not supported")
    case .Layer:
        out.payload = readChunkLayer(payloadData)
    case .Cel:
        out.payload = readChunkCel(payloadData)
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
        out.payload = readChunkUserData(payloadData)
    case .Slice:
        out.payload = readChunkSlice(payloadData)
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

    ctx := Ctx {
        colorDepth     = header.colorDepth,
        layersHaveUUID = .LayersHaveUUID in header.flags,
    }
    context.user_ptr = &ctx

    fmt.printfln("%#v", header)

    frame: Frame
    frame, offset = readFrame(aseData[pointer:])
    pointer += offset

    fmt.printfln("%#v", frame)
}
