local err = require("santoku.err")
local compat = require("santoku.compat")
local vec = require("santoku.vector")
local gen = require("santoku.gen")
local str = require("santoku.string")
local sys = require("santoku.system")
local fs = require("santoku.fs")

local M = {}

M.MT = {
  __index = M,
  __call = function(M, ...)
    return M.bundle(...)
  end
}

M.write_deps = function (check, modules, infile, outfile)
  local depsfile = outfile .. ".d"
  local out = gen.chain(
      gen.pack(outfile, ": "),
      gen.vals(modules):map(gen.vals):flatten():intersperse(" "),
      gen.pack("\n", depsfile, ": ", infile))
    :vec():concat()
  check(fs.writefile(depsfile, out))
end

M.addmod = function (check, modules, mod, path, cpath)
  if not (modules.lua[mod] or modules.c[mod]) then
    local fp, typ = check(M.searchpaths(mod, path, cpath))
    modules[typ][mod] = fp
    return fp, typ
  end
end

M.parsemodule = function (check, mod, modules, ignores, path, cpath)
  if ignores[mod] then
    return
  end
  local fp, typ = M.addmod(check, modules, mod, path, cpath)
  if typ == "lua" then
    M.parsemodules(check, fp, modules, ignores, path, cpath)
  end
end

M.parsemodules = function (check, infile, modules, ignores, path, cpath)
  check(fs.lines(infile))
    :map(function (line)
      -- TODO: The second match causes the bundler
      -- to skip any lines with the word
      -- 'require' in quotes, which may not be
      -- right
      -- if line:match("^%s*%-%-") or line:match("\"[^\"]*require[^\"]*\"") then
      if line:match("^%s*%-%-") then
        return gen.empty()
      else
        -- TODO: This pattern matches
        -- require("abc'). Notice the quotes.
        local pat = "require%(?[^%S\n]*[\"']([^\"']*)['\"][^%S\n]*%)?"
        return gen.ivals(str.match(line, pat))
      end
    end)
    :flatten()
    :each(function (mod)
      M.parsemodule(check, mod, modules, ignores, path, cpath)
    end)
end

M.parseinitialmodules = function (check, infile, mods, ignores, path, cpath)
  local modules = { c = {}, lua = {} }
  gen.ivals(mods):each(function(mod)
    M.parsemodule(check, mod, modules, ignores, path, cpath)
  end)
  M.parsemodules(check, infile, modules, ignores, path, cpath)
  return modules
end

M.searchpaths = function (mod, path, cpath)
  local fp0, err0 = compat.searchpath(mod, path) -- luacheck: ignore
  if fp0 then
    return true, fp0, "lua"
  end
  local fp1, err1 = compat.searchpath(mod, cpath) -- luacheck: ignore
  if fp1 then
    return true, fp1, "c"
  end
  return false, err0, err1
end

M.mergelua = function (modules, infile, mods)
  return err.pwrap(function (check)
    local ret = vec()
    gen.pairs(modules.lua):each(function (mod, fp)
      local data = check(fs.readfile(fp))
      ret:append("package.preload[\"", mod, "\"] = function ()\n\n", data, "\nend\n")
    end)
    gen.ivals(mods):each(function (mod)
      ret:append("require(\"", mod, "\")\n")
    end)
    ret:append("\n", check(fs.readfile(infile)))
    return ret:concat()
  end)
end

M.bundle = function (infile, outdir, opts)
  opts = opts or {}
  opts.mods = vec.wrap(opts.mods)
  opts.env = vec.wrap(opts.env)
  opts.flags = vec.wrap(opts.flags)
  local ignores = gen.ivals(opts.ignores or {}):set()
  return err.pwrap(function (check)
    opts.path = opts.path or os.getenv("LUA_PATH")
    opts.cpath = opts.cpath or os.getenv("LUA_CPATH")
    opts.outprefix = opts.outprefix or fs.splitexts(fs.basename(infile)).name
    local modules = M.parseinitialmodules(check, infile, opts.mods, ignores, opts.path, opts.cpath)
    local outluafp = fs.join(outdir, opts.outprefix .. ".lua")
    local outluadata = check(M.mergelua(modules, infile, opts.mods))
    check(fs.mkdirp(fs.dirname(outluafp)))
    check(fs.writefile(outluafp, outluadata))
    local outluacfp
    if opts.luac then
      if opts.luac == true then
        opts.luac = "luac -s -o %output %input"
      end
      outluacfp = fs.join(outdir, opts.outprefix .. ".luac")
      opts.luac = str.interp(opts.luac, { input = outluafp, output = outluacfp })
      local args = str.split(opts.luac)
      check(sys.execute(args:unpack()))
    else
      outluacfp = outluafp
    end
    opts.xxd = opts.xxd or "xxd -i -n data"
    local outluahfp = fs.join(outdir, opts.outprefix .. ".h")
    check(sys.execute(str.split(opts.xxd):append(outluacfp, outluahfp):unpack()))
    local outcfp = fs.join(outdir, opts.outprefix .. ".c")
    local outmainfp = fs.join(outdir, opts.outprefix)
    if opts.deps then
      M.write_deps(check, modules, infile, opts.depstarget or outmainfp)
    end
    check(fs.writefile(outcfp, table.concat({[[
      #include "lua.h"
      #include "lualib.h"
      #include "lauxlib.h"
    ]], (opts.env.n > 0 or opts.close == nil) and [[
      #include "stdlib.h"
    ]] or "", check(fs.readfile(outluahfp)), [[
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
    ]], gen.pairs(modules.c):map(function (mod)
      local sym = "luaopen_" .. string.gsub(mod, "%.", "_")
      return "int " .. sym .. "(lua_State *L);"
    end):concat("\n"), "\n", (opts.close == nil) and [[
      lua_State *L = NULL;
      void __tk_bundle_atexit (void) {
        if (L != NULL)
          lua_close(L);
      }
    ]] or "", [[
      int main (int argc, char **argv) {
    ]], gen.ivals(opts.env):map(function (e)
      return string.format("setenv(%s, %s, 1);", str.quote(e[1]), str.quote(e[2]))
    end):concat(), "\n", [[
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
    ]], gen.pairs(modules.c):map(function (mod)
      local sym = "luaopen_" .. string.gsub(mod, "%.", "_")
      return str.interp("__luaL_requiref(L, \"%mod\", %sym, 0);", {
        mod = mod,
        sym = sym
      })
    end):concat("\n"), "\n", [[
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
    ]]})))
    opts.cc = opts.cc or "cc"
    local args = vec()
    args:append(opts.cc, outcfp)
    args:extend(opts.flags)
    gen.pairs(modules.c)
      :each(function (_, fp)
        args:append(fp)
      end)
    io.stderr:write(args:concat(" ") .. "\n")
    io.stderr:flush()
    args:append("-o", outmainfp)
    check(sys.execute(args:unpack()))
  end)
end

return setmetatable(M, M.MT)
