local test = require("santoku.test")

local bundle = require("santoku.bundle")

local iter = require("santoku.iter")
local first = iter.first
local each = iter.each

local sys = require("santoku.system")
local sh = sys.sh

local str = require("santoku.string")
local stripprefix = str.stripprefix

local fs = require("santoku.fs")
local exists = fs.exists
local files = fs.files
local join = fs.join
local mkdirp = fs.mkdirp
local rm = fs.rm
local stripextension = fs.stripextension

test("bundle", function ()

  local infile = "test/res/bundle/test.lua"
  local outdir = "test/res/bundle/test"

  mkdirp(outdir, true)

  each(function (fp)
    return rm(fp)
  end, files(outdir))

  local incdir = first(sh({ "luarocks", "config", "variables.LUA_INCDIR" }))
  local libdir = first(sh({ "luarocks", "config", "variables.LUA_LIBDIR" }))
  local libfile = first(sh({ "luarocks", "config", "variables.LUA_LIBDIR_FILE" }))

  local libname = stripprefix(stripextension(libfile), "lib")

  bundle(infile, outdir, {
    -- luac = "luajit -b %input %output",
    debug = true,
    flags = { "-I", incdir, "-L", libdir , "-l", libname, "-l", "m" }
  })

  assert(exists(join(outdir, "test.lua")))
  -- assert(exists(join(outdir, "test.luac")))
  assert(exists(join(outdir, "test.h")))
  assert(exists(join(outdir, "test.c")))
  assert(exists(join(outdir, "test")))

end)
