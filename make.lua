local env = {
  name = "santoku-bundle",
  version = "0.0.40-1",
  variable_prefix = "TK_BUNDLE",
  license = "MIT",
  public = true,
  dependencies = {
    "lua >= 5.1",
    "lpeg >= 1.0.0",
    "santoku >= 0.0.314-1",
    "santoku-system >= 0.0.61-1",
    "santoku-fs >= 0.0.41-1",
    "santoku-mustache >= 0.0.14-1"
  },
}

env.homepage = "https://github.com/treadwelllane/lua-" .. env.name
env.tarball = env.name .. "-" .. env.version .. ".tar.gz"
env.download = env.homepage .. "/releases/download/" .. env.version .. "/" .. env.tarball

return {
  env = env,
}
