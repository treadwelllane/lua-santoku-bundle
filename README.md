<p align="center">
  <img src="https://santoku.dev/logo-santoku-bundle.png" height="64" alt="santoku-bundle">
</p>

# santoku-bundle

Turns a Lua entry script and everything it transitively requires into a single standalone
executable. It scans for `require` calls with lpeg, resolves each module to a file, merges
the Lua sources, generates a C program around them, and invokes the C compiler.

## Install

```sh
luarocks install santoku-bundle
```

## Example

```lua
local bundle = require("santoku.bundle")

bundle("src/main.lua", "out", {
  flags = { "-I", incdir, "-L", libdir, "-l", "lua5.1", "-l", "m" }
})
```

That writes `out/main.lua` (the merged source), `out/main.c` (the generated program), and
`out/main` (the linked executable). C modules found during the scan are linked in and
registered at startup.

## Documentation

Runnable examples and the full API: [santoku.dev](https://santoku.dev/#santoku-bundle).

For agents and LLM tooling: [llms.txt](https://santoku.dev/llms.txt) for the index,
[llms-full.txt](https://santoku.dev/llms-full.txt) for every documented example.

## Tests

The tests are the spec. For the exhaustive surface, read them:
[`test/spec/santoku/bundle.lua`](test/spec/santoku/bundle.lua).

## License

MIT, see [LICENSE](LICENSE).

## More examples

```lua
local test = require("santoku.test")

local err = require("santoku.error")
local assert = err.assert

local validate = require("santoku.validate")
local eq = validate.isequal

local bundle = require("santoku.bundle")

local arr = require("santoku.array")
local fs = require("santoku.fs")
local str = require("santoku.string")
local sys = require("santoku.system")

test("bundle a lua entry script into a standalone executable", function ()

  local infile = "test/res/bundle/test.lua"
  local outdir = "test/res/bundle/readme"

  fs.mkdirp(outdir, true)

  arr.ieach(function (fp)
    return fs.rm(fp)
  end, fs.files(outdir))

  local incdir = sys.sh({ "luarocks", "config", "variables.LUA_INCDIR" })()
  local libdir = sys.sh({ "luarocks", "config", "variables.LUA_LIBDIR" })()
  local libfile = sys.sh({ "luarocks", "config", "variables.LUA_LIBDIR_FILE" })()

  local libname = str.stripprefix(fs.stripextension(libfile), "lib")

  bundle(infile, outdir, {
    flags = { "-I", incdir, "-L", libdir, "-l", libname, "-l", "m" }
  })

  assert(eq(true, (fs.exists(fs.join(outdir, "test.lua")))))
  assert(eq(true, (fs.exists(fs.join(outdir, "test.c")))))
  assert(eq(true, (fs.exists(fs.join(outdir, "test")))))

end)
```
