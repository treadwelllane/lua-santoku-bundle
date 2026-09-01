local env = {
  name = "santoku-bundle",
  version = "2.0.3-1",
  variable_prefix = "TK_BUNDLE",
  license = "MIT",
  public = true,
  dependencies = {
    "lua == 5.1",
    "santoku-lpeg >= 2.0.0, < 3.0.0",
    "santoku >= 2.0.0, < 3.0.0",
    "santoku-system >= 2.0.0, < 3.0.0",
    "santoku-fs >= 2.0.0, < 3.0.0",
    "santoku-mustache >= 2.0.0, < 3.0.0"
  },
}

env.homepage = "https://github.com/birchpointswe/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return {
  env = env,
}
