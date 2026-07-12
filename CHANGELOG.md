# Changelog

## 0.1.0

- Initial release.
- `MikaCredoRules.NoApplicationEnvOutsideConfig` — flags any read or write of
  application env outside a config module. Configurable via `:config_files`,
  `:functions`, and `:erlang_functions`.
- The check resolves aliases from a flat, file-level table, so `alias Application, as:
  App` + `App.get_env/2`, `Elixir.Application.get_env/2`, and `:application.get_env/2`
  are all caught. Aliasing another module *to* `Application` correctly suppresses it.
