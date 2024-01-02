local env = {

  name = "santoku-bundle",
  version = "0.0.18-1",
  variable_prefix = "TK_BUNDLE",
  license = "MIT",
  public = true,

  dependencies = {
    "lua >= 5.1",
    "santoku >= 0.0.159-1",
    "santoku-system >= 0.0.9-1",
    "santoku-fs >= 0.0.13-1"
  },

  test = {
    dependencies = {
      "santoku-test >= 0.0.7-1",
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
