# santoku-bundle

Lua script bundler that creates standalone executables from Lua programs and their dependencies.

## Modules

### `santoku.bundle`

Bundle Lua scripts and their dependencies into standalone executables.

#### `bundle(infile, outdir, opts)`

Creates a standalone executable from a Lua script by bundling all dependencies.

**Parameters:**
- `infile` (string) - Path to the input Lua script
- `outdir` (string) - Output directory for generated files
- `opts` (table) - Configuration options:
  - `mods` (table) - Additional modules to preload
  - `env` (table) - Environment variables to set at runtime
  - `flags` (table) - Compiler flags for building the executable
  - `ignores` (table) - Modules to ignore during dependency resolution
  - `path` (string) - Custom LUA_PATH for module resolution
  - `cpath` (string) - Custom LUA_CPATH for C module resolution
  - `outprefix` (string) - Output file prefix (defaults to input basename)
  - `luac` (string|boolean) - Lua compiler command or true for default
  - `xxd` (string) - Command to convert bytecode to C header (default: "xxd -i -n data")
  - `cc` (string) - C compiler command (default: "cc")
  - `deps` (boolean) - Generate dependency file for make
  - `depstarget` (string) - Target name for dependency file
  - `close` (boolean) - Whether to close Lua state on exit

The bundler automatically discovers dependencies by parsing `require()` statements and generates a C program with embedded Lua runtime. Both Lua and C modules are supported with proper linking.

## Related Projects

- [santoku-cli](../lua-santoku-cli) - Command-line interface with bundling support

## License

MIT License

Copyright 2025 Matthew Brooks

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.