# santoku-bundle

A build-time bundler that turns a Lua entry script and its dependencies into a single
C program, then compiles that program into a standalone executable. Built on base
[`santoku`](../lua-santoku/README.md) (string, array, env, fs glue),
[`santoku-fs`](../lua-santoku-fs/README.md) (file I/O, paths),
[`santoku-system`](../lua-santoku-system/README.md) (invoking the C compiler and `luac`),
[`santoku-mustache`](../lua-santoku-mustache/README.md) (the C source templates), and
[lpeg](https://www.inf.puc-rio.br/~roberto/lpeg/) (the `require()` scanner). The
[toku](../lua-santoku-cli/README.md) build/release flow calls this to produce the
shipped binary for a project.

This README is a usage guide, not an API reference. The tests are the spec:
`test/spec/santoku/bundle.lua` exercises the default flow against the fixture
`test/res/bundle/test.lua`. Read that for the full assertion set; read this for how the
entry point is called and what it emits.

The module returns a single function. Dependency resolution, the type system of the
file/path arguments, and the compiler invocation belong to the dependencies listed above;
this README does not re-document them.

## What it does

`require("santoku.bundle")` returns one function:

```
bundle(infile, outdir, opts)
```

It reads `infile`, scans it (and every Lua module it transitively `require`s) with an lpeg
parser that finds `require` calls while skipping strings and comments, resolves each module
to a file via `env.searchpath` over `opts.path`/`opts.cpath`, and classifies it as Lua or C.
It then writes generated artifacts into `outdir` and shells out to the C compiler to link the
final executable. C modules found during the scan are linked in and registered through a
generated `luaL_requiref` at startup.

The output prefix defaults to the input basename with extensions stripped (`opts.outprefix`
overrides). For an input named `test.lua` the default flow writes `test.lua` (the merged
Lua source), `test.c` (the generated C program), and `test` (the linked executable).

## Options

`opts` is a table. All fields are optional except that `infile`, `outdir`, and `opts`
itself must be present.

- `mods`: extra module names to preload and `require` ahead of the entry file.
- `env`: list of `{name, value}` pairs set with `setenv` at the start of the executable.
- `flags`: compiler flags spread into the compile command (include/lib dirs, `-l` links).
- `ignores`: module names to skip during dependency resolution.
- `path` / `cpath`: search paths for Lua / C module resolution (default `LUA_PATH` /
  `LUA_CPATH`).
- `outprefix`: output file prefix.
- `cc`: C compiler command (default from `CC`, else `cc`).
- `close`: when omitted, the state is closed via `atexit`; when `true`, closed explicitly at
  the end of `main`.
- `deps`: write a `<output>.d` make dependency file listing all resolved sources;
  `depstarget` overrides the make target name.
- `luac`: precompile the merged Lua to bytecode before embedding. `true` uses
  `luac -s -o %output %input`; a string is an `str.interp` template with `%input`/`%output`.
- `binary`: embed bytecode as a raw C byte array instead of the default base64 string that is
  decoded at startup.
- `files`: alternate output mode (see below).

## Default mode  ·  test/spec/santoku/bundle.lua

The default mode merges every resolved Lua module into one source string (each wrapped in a
`package.preload[name]` entry), optionally precompiles it with `luac`, embeds the result into
a generated C program (base64 by default, raw bytes with `binary`), and compiles that program.
The canonical call, from the anchor test:

```lua
local bundle = require("santoku.bundle")
local fs = require("santoku.fs")

bundle("test/res/bundle/test.lua", "test/res/bundle/test", {
  flags = { "-I", incdir, "-L", libdir, "-l", libname, "-l", "m" }
})

assert(fs.exists("test/res/bundle/test/test.lua"))
assert(fs.exists("test/res/bundle/test/test.c"))
assert(fs.exists("test/res/bundle/test/test"))
```

Here `incdir`, `libdir`, and `libname` come from `luarocks config` queries in the test, so
the generated C program links against the host Lua runtime.

covers: default merged-Lua bundle, dependency scan over the fixture's `require`s, `flags`
passthrough, and the three emitted artifacts (`.lua`, `.c`, executable).

## Files mode

When `opts.files` is set, the bundler does not merge or embed the Lua source. Instead it
emits a C program that runs the entry file from an embedded virtual filesystem (passed as
`--embed-file` flags, the form Emscripten expects) and computes a shared path prefix so the
VFS paths are clean. This mode keeps original filenames in tracebacks for clearer error
reporting. It is not exercised by the current test; treat the default mode as the supported
path until a files-mode anchor exists.

## License

MIT License

Copyright 2025 Birch Point SWE

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
