# ACE
A little single-file library for parsing [Aseprite files](https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md)
using the Odin programming language.

The name comes from me constantly misspelling "Aseprite" as "Aceprite".

> [!WARNING]
> `ACE` implements only a subset of the file spec that I need.

# Usage
Just copy-paste the `ace.odin` file into your project and use the `readFile` or
`readFileFromMemory` functions to get the file contents.

> [!IMPORTANT]
> The library does not currently provide any means to properly free all the
> memory it allocates as it is not needed for my current use cases!

## Example

```odin
package test
import "ace"

@(rodata)
SOMETHING_DATA := #load("./something.ase")

main :: proc() {
    file := readFile("./something.ase")
    file2 := readFileFromMemory(SOMETHING_DATA)
}
```
