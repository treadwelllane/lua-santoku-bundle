local env = {

  name = "santoku-bundle",
  version = "0.0.33-1",
  variable_prefix = "TK_BUNDLE",
  license = "MIT",
  public = true,

  dependencies = {
    "lua >= 5.1",
    "lpeg >= 1.0.0",
    "santoku >= 0.0.294-1",
    "santoku-system >= 0.0.56-1",
    "santoku-fs >= 0.0.34-1",
    "santoku-mustache >= 0.0.2-1"
  },

  test = {
    dependencies = {
      "luacov >= 0.15.0-1",
    }
  },

}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return {
  type = "lib",
  env = env,
}
