local err = require("santoku.error")
local lpeg = require("lpeg")
local str = require("santoku.string")
local iter = require("santoku.iter")
local validate = require("santoku.validate")
local arr = require("santoku.array")
local sys = require("santoku.system")
local fun = require("santoku.functional")
local fs = require("santoku.fs")
local env = require("santoku.env")
local mch = require("santoku.mustache")

local P, R, S, C, Ct, Cmt = lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Ct, lpeg.Cmt

local function build_long_bracket ()
  return Cmt(P"[" * C(P"="^0) * P"[", function(s, pos, level)
    local close_pattern = "]" .. level .. "]"
    local close_start, close_end = s:find(close_pattern, pos, true)
    if close_start then
      local content = s:sub(pos, close_start - 1)
      return close_end + 1, content
    end
    return nil
  end)
end

local parsemodules

local function searchpaths (mod, path, cpath)
  local fp0, err1 = env.searchpath(mod, path)
  if fp0 then
    return fp0, "lua"
  end
  local fp1, err2 = env.searchpath(mod, cpath)
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

local function build_long_bracket_skip()
  return Cmt(P"[" * C(P"="^0) * P"[", function(s, pos, level)
    local close_pattern = "]" .. level .. "]"
    local close_start, close_end = s:find(close_pattern, pos, true)
    if close_start then
      return close_end + 1
    end
    return nil
  end)
end

local ws = S" \t\n\r"^0
local long_bracket_cap = build_long_bracket()
local short_string_cap = P'"' * C((P'\\' * 1 + (1 - S'"\n'))^0) * P'"' + P"'" * C((P'\\' * 1 + (1 - S"'\n"))^0) * P"'"
local string_cap = long_bracket_cap + short_string_cap
local long_bracket_skip = build_long_bracket_skip()
local short_string_skip = P'"' * (P'\\' * 1 + (1 - S'"\n'))^0 * P'"' + P"'" * (P'\\' * 1 + (1 - S"'\n"))^0 * P"'"
local string_skip = long_bracket_skip + short_string_skip
local comment = P"--" * long_bracket_skip + P"--" * (1 - P"\n")^0
local require_kw = P"require" * -(R("az", "AZ", "09") + P"_")
local require_call = require_kw * ws * ((P"(" * ws * string_cap * ws * P")") + string_cap) / fun.id
local require_parser = Ct((require_call + comment + string_skip + 1)^0)

parsemodules = function (infile, modules, ignores, path, cpath)
  local content = fs.readfile(infile)
  local matches = require_parser:match(content)

  if matches then
    for _, mod in ipairs(matches) do
      if type(mod) == "string" and #mod > 0 then
        parsemodule(mod, modules, ignores, path, cpath)
      end
    end
  end
end

local function parseinitialmodules (infile, mods, ignores, path, cpath)
  local modules = { c = {}, lua = {} }
  for mod in iter.ivals(mods) do
    parsemodule(mod, modules, ignores, path, cpath)
  end
  parsemodules(infile, modules, ignores, path, cpath)
  return modules
end

local function mergelua (modules, infile, mods)
  local ret = {}
  for mod, fp in iter.pairs(modules.lua) do
    local data = fs.readfile(fp)
    arr.push(ret, "package.preload[\"", mod, "\"] = function ()\n\n", data, "\nend\n")
  end
  for mod in iter.ivals(mods) do
    arr.push(ret, "require(\"", mod, "\")\n")
  end
  arr.push(ret, "\n", fs.readfile(infile))
  return arr.concat(ret)
end

local function write_deps (modules, infile, outfile)
  local depsfile = outfile .. ".d"
  local out = { outfile, ": " }
  arr.extend(out, iter.collect(iter.intersperse(" ", iter.flatten(iter.map(iter.vals, iter.vals(modules))))))
  arr.push(out, "\n", depsfile, ": ", infile)
  fs.writefile(depsfile, arr.concat(out))
end

local function to_c_array (data)
  local ret = {}
  for i = 1, #data do
    if i > 1 then
      arr.push(ret, ",")
    end
    if (i - 1) % 16 == 0 then
      arr.push(ret, "\n  ")
    end
    arr.push(ret, string.format("0x%02x", string.byte(data, i)))
  end
  return arr.concat(ret)
end

local function bundle (infile, outdir, opts)

  err.assert(validate.isstring(infile))
  err.assert(validate.isstring(outdir))
  err.assert(validate.hasindex(opts))

  opts.mods = opts.mods or {}
  opts.env = opts.env or {}
  opts.flags = opts.flags or {}
  opts.ignores = opts.ignores or {}

  for k in iter.ivals(opts.ignores) do
    opts.ignores[k] = true
  end

  opts.path = opts.path or env.var("LUA_PATH", nil)
  opts.cpath = opts.cpath or env.var("LUA_CPATH", nil)
  opts.outprefix = opts.outprefix or fs.stripextensions(fs.basename(infile))

  local modules = parseinitialmodules(infile, opts.mods, opts.ignores, opts.path, opts.cpath)

  local outluafp = fs.join(outdir, opts.outprefix .. ".lua")
  local outluadata = mergelua(modules, infile, opts.mods)

  fs.mkdirp(outdir)
  fs.mkdirp(fs.dirname(outluafp))
  fs.writefile(outluafp, outluadata)

  local outluacfp

  if opts.luac then
    if opts.luac == true then
      opts.luac = "luac -s -o %output %input"
    end
    outluacfp = fs.join(outdir, opts.outprefix .. ".luac")
    opts.luac = str.interp(opts.luac, { input = outluafp, output = outluacfp })
    sys.execute(iter.collect(iter.map(string.sub, str.splits(opts.luac, "%s+"))))
  else
    outluacfp = outluafp
  end

  local bytecode = fs.readfile(outluacfp)

  local outcfp = fs.join(outdir, opts.outprefix .. ".c")
  local outmainfp = fs.join(outdir, opts.outprefix)

  if opts.deps then
    write_deps(modules, infile, opts.depstarget or outmainfp)
  end

  local c_modules = {}
  for mod in iter.pairs(modules.c) do
    local sym = "luaopen_" .. str.gsub(mod, "%.", "_")
    arr.push(c_modules, { symbol = sym, module = mod })
  end

  local env_vars = {}
  for e in iter.ivals(opts.env) do
    arr.push(env_vars, { name = str.quote(e[1]), value = str.quote(e[2]) })
  end

  local bytecode_data, bytecode_len
  if opts.binary then
    bytecode_data = to_c_array(bytecode)
    bytecode_len = #bytecode
  else
    bytecode_data = str.quote(str.to_base64(bytecode))
  end

  local c_code = mch([[
    #include "lua.h"
    #include "lualib.h"
    #include "lauxlib.h"
    #include "stdlib.h"
    {{^binary}}
    #include "string.h"

    static unsigned char base64_decode_char(char c) {
      if (c >= 'A' && c <= 'Z') return c - 'A';
      if (c >= 'a' && c <= 'z') return c - 'a' + 26;
      if (c >= '0' && c <= '9') return c - '0' + 52;
      if (c == '+') return 62;
      if (c == '/') return 63;
      return 0;
    }

    static size_t base64_decode(const char *input, size_t input_len, unsigned char **output) {
      size_t output_len = (input_len * 3) / 4;
      size_t padding = 0;
      if (input_len >= 2) {
        if (input[input_len - 1] == '=') padding++;
        if (input[input_len - 2] == '=') padding++;
      }
      output_len -= padding;
      *output = malloc(output_len);
      if (!*output) return 0;
      size_t j = 0;
      unsigned char buf[4];
      for (size_t i = 0; i < input_len; i += 4) {
        buf[0] = base64_decode_char(input[i]);
        buf[1] = base64_decode_char(input[i + 1]);
        buf[2] = input[i + 2] == '=' ? 0 : base64_decode_char(input[i + 2]);
        buf[3] = input[i + 3] == '=' ? 0 : base64_decode_char(input[i + 3]);
        (*output)[j++] = (buf[0] << 2) | (buf[1] >> 4);
        if (j < output_len) (*output)[j++] = (buf[1] << 4) | (buf[2] >> 2);
        if (j < output_len) (*output)[j++] = (buf[2] << 6) | buf[3];
      }
      return output_len;
    }

    static const char *data_base64 = {{{bytecode_data}}};
    {{/binary}}
    {{#binary}}

    static const unsigned char data[] = { {{{bytecode_data}}}
    };
    static const size_t data_len = {{{bytecode_len}}};
    {{/binary}}

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

    {{#c_modules}}
    int {{{symbol}}}(lua_State *L);
    {{/c_modules}}

    lua_State *L = NULL;

    {{#auto_close}}
    void __tk_bundle_atexit (void) {
      if (L != NULL)
        lua_close(L);
    }
    {{/auto_close}}

    int main (int argc, char **argv) {
    {{#env_vars}}
      setenv({{{name}}}, {{{value}}}, 1);
    {{/env_vars}}
      L = luaL_newstate();
      int rc = 0;
    {{^binary}}
      unsigned char *decoded_data = NULL;
      size_t data_len = 0;
    {{/binary}}
    {{#auto_close}}
      if (0 != (rc = atexit(__tk_bundle_atexit)))
        goto err;
    {{/auto_close}}
      if (L == NULL)
        return 1;
    {{^binary}}
      data_len = base64_decode(data_base64, strlen(data_base64), &decoded_data);
      if (data_len == 0 || decoded_data == NULL) {
        fprintf(stderr, "Failed to decode bytecode\n");
        return 1;
      }
    {{/binary}}
      luaL_openlibs(L);
    {{#c_modules}}
      __luaL_requiref(L, "{{{module}}}", {{{symbol}}}, 0);
    {{/c_modules}}
    {{#binary}}
      if (0 != (rc = luaL_loadbuffer(L, (const char *)data, data_len, "bundle")))
    {{/binary}}
    {{^binary}}
      if (0 != (rc = luaL_loadbuffer(L, (const char *)decoded_data, data_len, "bundle")))
    {{/binary}}
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
    {{^binary}}
      if (decoded_data != NULL)
        free(decoded_data);
    {{/binary}}
    {{#explicit_close}}
      lua_close(L);
    {{/explicit_close}}
      return rc;
    }
  ]])({
    bytecode_data = bytecode_data,
    bytecode_len = bytecode_len,
    binary = opts.binary,
    c_modules = c_modules,
    env_vars = env_vars,
    auto_close = opts.close == nil,
    explicit_close = opts.close == true
  })

  fs.writefile(outcfp, c_code)
  opts.cc = opts.cc or env.var("CC", "cc")
  local args = {}
  arr.push(args, opts.cc, outcfp)
  arr.extend(args, opts.flags)
  for fp in iter.vals(modules.c) do
    arr.push(args, fp)
  end
  arr.push(args, "-o", outmainfp)
  print(arr.concat(args, " "))
  sys.execute(args)
end

return bundle
