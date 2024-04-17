local err = require("santoku.error")
local assert = err.assert

local str = require("santoku.string")
local smatches = str.matches
local squote = str.quote
local ssplits = str.splits
local sinterp = str.interp
local smatch = str.match
local gsub = str.gsub
local sformat = str.format
local ssub = str.sub

local iter = require("santoku.iter")
local pairs = iter.pairs
local intersperse = iter.intersperse
local flatten = iter.flatten
local first = iter.first
local ivals = iter.ivals
local vals = iter.vals
local collect = iter.collect
local map = iter.map

local validate = require("santoku.validate")
local isstring = validate.isstring
local hasindex = validate.hasindex

local arr = require("santoku.array")
local push = arr.push
local concat = arr.concat
local extend = arr.extend

local sys = require("santoku.system")
local execute = sys.execute

local fs = require("santoku.fs")
local mkdirp = fs.mkdirp
local lines = fs.lines
local readfile = fs.readfile
local writefile = fs.writefile
local basename = fs.basename
local dirname = fs.dirname
local stripextensions = fs.stripextensions
local join = fs.join

local env = require("santoku.env")
local searchpath = env.searchpath
local var = env.var

local parsemodules

local function searchpaths (mod, path, cpath)
  local fp0, err1 = searchpath(mod, path) -- luacheck: ignore
  if fp0 then
    return fp0, "lua"
  end
  local fp1, err2 = searchpath(mod, cpath) -- luacheck: ignore
  if fp1 then
    return fp1, "c"
  end
  error(err1 or err2)
end

local function addmod (modules, mod, path, cpath)
  if not (modules.lua[mod] or modules.c[mod]) then
    local fp, typ = searchpaths(mod, path, cpath)
    modules[typ][mod] = fp
    return fp, typ
  end
end

local function parsemodule (mod, modules, ignores, path, cpath)
  if ignores[mod] then
    return
  end
  local fp, typ = addmod(modules, mod, path, cpath)
  if typ == "lua" then
    parsemodules(fp, modules, ignores, path, cpath)
  end
end

local require_pat = "require%(?[^%S\n]*[\"']([^\"']*)['\"][^%S\n]*%)?"

parsemodules = function (infile, modules, ignores, path, cpath)
  for chunk, ls, le in lines(infile) do
    if not first(smatches(chunk, "^%s*%-%-", false, ls, le)) then
      local mod = smatch(chunk, require_pat, ls)
      if mod then
        parsemodule(mod, modules, ignores, path, cpath)
      end
    end
  end
end

local function parseinitialmodules (infile, mods, ignores, path, cpath)
  local modules = { c = {}, lua = {} }
  for mod in ivals(mods) do
    parsemodule(mod, modules, ignores, path, cpath)
  end
  parsemodules(infile, modules, ignores, path, cpath)
  return modules
end

local function mergelua (modules, infile, mods)
  local ret = {}
  for mod, fp in pairs(modules.lua) do
    local data = readfile(fp)
    push(ret, "package.preload[\"", mod, "\"] = function ()\n\n", data, "\nend\n")
  end
  for mod in ivals(mods) do
    push(ret, "require(\"", mod, "\")\n")
  end
  push(ret, "\n", readfile(infile))
  return concat(ret)
end

local function write_deps (modules, infile, outfile)
  local depsfile = outfile .. ".d"
  local out = { outfile, ": " }
  extend(out, collect(intersperse(" ", flatten(map(vals, vals(modules))))))
  push(out, "\n", depsfile, ": ", infile)
  writefile(depsfile, concat(out))
end

local function bundle (infile, outdir, opts)

  assert(isstring(infile))
  assert(isstring(outdir))
  assert(hasindex(opts))

  opts.mods = opts.mods or {}
  opts.env = opts.env or {}
  opts.flags = opts.flags or {}
  opts.ignores = opts.ignores or {}

  for k in ivals(opts.ignores) do
    opts.ignores[k] = true
  end

  opts.path = opts.path or var("LUA_PATH", nil)
  opts.cpath = opts.cpath or var("LUA_CPATH", nil)
  opts.outprefix = opts.outprefix or stripextensions(basename(infile))

  local modules = parseinitialmodules(infile, opts.mods, opts.ignores, opts.path, opts.cpath)

  local outluafp = join(outdir, opts.outprefix .. ".lua")
  local outluadata = mergelua(modules, infile, opts.mods)

  mkdirp(dirname(outluafp))
  writefile(outluafp, outluadata)

  local outluacfp

  if opts.luac then
    if opts.luac == true then
      opts.luac = "luac -s -o %output %input"
    end
    outluacfp = join(outdir, opts.outprefix .. ".luac")
    opts.luac = sinterp(opts.luac, { input = outluafp, output = outluacfp })
    execute(collect(map(ssub, ssplits(opts.luac, "%s+"))))
  else
    outluacfp = outluafp
  end

  opts.xxd = opts.xxd or "xxd -i -n data"

  local outluahfp = join(outdir, opts.outprefix .. ".h")
  execute(push(collect(map(ssub, ssplits(opts.xxd, "%s+"))), outluacfp, outluahfp))

  local outcfp = join(outdir, opts.outprefix .. ".c")
  local outmainfp = join(outdir, opts.outprefix)

  if opts.deps then
    write_deps(modules, infile, opts.depstarget or outmainfp)
  end

  writefile(outcfp, concat({[[
    #include "lua.h"
    #include "lualib.h"
    #include "lauxlib.h"
  ]], (#opts.env > 0 or opts.close == nil) and [[
    #include "stdlib.h"
  ]] or "", readfile(outluahfp), [[
    /* Source: https://github.com/lunarmodules/lua-compat-5.3 */
#define lua_getfield(L, i, k) (lua_getfield((L), (i), (k)), lua_type((L), -1))
    int __lua_absindex (lua_State *L, int i) {
      if (i < 0 && i > LUA_REGISTRYINDEX)
        i += lua_gettop(L) + 1;
      return i;
    }
    int __luaL_getsubtable (lua_State *L, int i, const char *name) {
      int abs_i = __lua_absindex(L, i);
      luaL_checkstack(L, 3, "not enough stack slots");
      lua_pushstring(L, name);
      lua_gettable(L, abs_i);
      if (lua_istable(L, -1))
        return 1;
      lua_pop(L, 1);
      lua_newtable(L);
      lua_pushstring(L, name);
      lua_pushvalue(L, -2);
      lua_settable(L, abs_i);
      return 0;
    }
    void __luaL_requiref (lua_State *L, const char *modname,
                                     lua_CFunction openf, int glb) {
      luaL_checkstack(L, 3, "not enough stack slots available");
      __luaL_getsubtable(L, LUA_REGISTRYINDEX, "_LOADED");
      if (lua_getfield(L, -1, modname) == LUA_TNIL) {
        lua_pop(L, 1);
        lua_pushcfunction(L, openf);
        lua_pushstring(L, modname);
        lua_call(L, 1, 1);
        lua_pushvalue(L, -1);
        lua_setfield(L, -3, modname);
      }
      if (glb) {
        lua_pushvalue(L, -1);
        lua_setglobal(L, modname);
      }
      lua_replace(L, -2);
    }
  ]], concat(collect(map(function (mod)
    local sym = "luaopen_" .. gsub(mod, "%.", "_")
    return "int " .. sym .. "(lua_State *L);"
  end, pairs(modules.c))), "\n"), "\n", (opts.close == nil) and [[
    lua_State *L = NULL;
    void __tk_bundle_atexit (void) {
      if (L != NULL)
        lua_close(L);
    }
  ]] or "", [[
    int main (int argc, char **argv) {
  ]], concat(collect(map(function (e)
    return sformat("setenv(%s, %s, 1);", squote(e[1]), squote(e[2]))
  end, ivals(opts.env)))), "\n", [[
  ]], [[
      L = luaL_newstate();
      int rc = 0;
  ]], (opts.close == nil) and [[
      if (0 != (rc = atexit(__tk_bundle_atexit)))
        goto err;
  ]] or "", [[
      if (L == NULL)
        return 1;
      luaL_openlibs(L);
  ]], concat(collect(map(function (mod)
    local sym = "luaopen_" .. gsub(mod, "%.", "_")
    return sinterp("__luaL_requiref(L, \"%mod\", %sym, 0);", {
      mod = mod,
      sym = sym
    })
  end, pairs(modules.c))), "\n"), "\n", [[
      if (0 != (rc = luaL_loadbuffer(L, (const char *)data, data_len, "bundle")))
        goto err;
      lua_createtable(L, argc, 0);
      for (int i = 0; i < argc; i ++) {
        lua_pushstring(L, argv[i]);
        lua_pushinteger(L, argc + 1);
        lua_settable(L, -3);
      }
      lua_setglobal(L, "arg");
      if (0 != (rc = lua_pcall(L, 0, 0, 0)))
        goto err;
      goto end;
    err:
      rc = 1;
      fprintf(stderr, "%s\n", lua_tostring(L, -1));
    end:
    ]], (opts.close == true) and [[
      lua_close(L);
    ]] or "", [[
      return rc;
    }
  ]]}))
  opts.cc = opts.cc or "cc"
  local args = {}
  push(args, opts.cc, outcfp)
  extend(args, opts.flags)
  for fp in vals(modules.c) do
    push(args, fp)
  end
  push(args, "-o", outmainfp)
  print(concat(args, " "))
  execute(args)
end

return bundle
