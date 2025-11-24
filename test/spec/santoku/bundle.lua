local test = require("santoku.test")
local bundle = require("santoku.bundle")
local iter = require("santoku.iter")
local sys = require("santoku.system")
local str = require("santoku.string")
local fs = require("santoku.fs")

test("bundle", function ()

  local infile = "test/res/bundle/test.lua"
  local outdir = "test/res/bundle/test"

  fs.mkdirp(outdir, true)

  iter.each(function (fp)
    return fs.rm(fp)
  end, fs.files(outdir))

  local incdir = iter.first(sys.sh({ "luarocks", "config", "variables.LUA_INCDIR" }))
  local libdir = iter.first(sys.sh({ "luarocks", "config", "variables.LUA_LIBDIR" }))
  local libfile = iter.first(sys.sh({ "luarocks", "config", "variables.LUA_LIBDIR_FILE" }))

  local libname = str.stripprefix(fs.stripextension(libfile), "lib")

  bundle(infile, outdir, {
    -- luac = "luajit -b %input %output",
    debug = true,
    flags = { "-I", incdir, "-L", libdir , "-l", libname, "-l", "m" }
  })

  assert(fs.exists(fs.join(outdir, "test.lua")))
  -- assert(fs.exists(fs.join(outdir, "test.luac")))
  assert(fs.exists(fs.join(outdir, "test.c")))
  assert(fs.exists(fs.join(outdir, "test")))

end)
