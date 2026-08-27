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
