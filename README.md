# devise_i18n.cr

A Crystal port of [heartcombo/devise-i18n](https://github.com/heartcombo/devise-i18n)
**1.16.1** — community translations for devise: 73 locales, a view
helper and the locale generator. All dictionaries are byte-identical
copies of the gem's `rails/locales/*.yml`, baked into the binary at
compile time and registered in `Devise::I18n.register_yaml` when the
shard is required; locale parsing is lazy (on first lookup).

> ⚠️ EXPERIMENTAL — DO NOT USE IN PRODUCTION YET.

## Installation

```yaml
dependencies:
  devise_i18n_cr:
    github: OrelSokolov/devise_i18n.cr
```

```sh
shards install
```

Requires the patched devise.cr (`Devise::I18n.register_yaml` API).

## Usage

```crystal
require "devise_i18n_cr"

Devise.locale = "ru"
Devise.t("devise.sessions.new.sign_in") # => "Войти"
```

## Feature comparison vs devise-i18n 1.16.1

| Feature | Original (devise-i18n) | Port (devise_i18n.cr) | Status |
|---|---|---|---|
| 73 community locales (`rails/locales/*.yml`) | ✅ | Byte-identical copies in `src/locales/` | ✅ |
| Railtie adds locale files to `I18n.load_path` at boot | ✅ | Dictionaries baked in at compile time, registered on require; no runtime file loads; lazy YAML parsing per locale | 🔶 |
| `ViewHelpers.fix_model_name_case` (downcase for `errors.messages.not_saved`, except `:de`) | ✅ | Same | ✅ |
| `rails g devise:i18n:locale ru` | ✅ | `DeviseI18n::LocaleGenerator.run(["ru", "-f", "-q"], root: ".")` copies to `config/locales/devise.views.<loc>.yml`; unknown locale raises | ✅ |
| All leaves of all 73 locales resolve via devise's I18n | ✅ | `Devise::I18n.translate` with interpolation stubs, `count: 1/2` pluralization, nil-keys, locale lists — oracle 1:1 | ✅ |
| `few`/`many` pluralization rules (rails-i18n procs) | ✅ | Readable only via explicit dot-path (`activerecord.models.user.few`) — same as ruby-I18n without rails-i18n (procs are not expressible in YAML) | 🔶 |
| other-only locales (ja/ko/id/km) with `count: 1` | raises `I18n::InvalidPluralizationData` | Returns nil (reflected in the oracle by a marker) | 🔶 |
| Railtie filter by `config.i18n.available_locales` | ✅ | Not ported — all locales register (equivalent to empty available_locales) | ❌ |
| Translated ERB views (`app/views/devise/**`) and `simple_form_for` templates | ✅ | Not ported (lands in devise.cr's `Devise::ViewsGenerator` when its views move to `t(".key")`) | ⬜ |
| `devise:i18n:views` generator | ✅ | Not ported | ⬜ |

## Deviations & Crystal-specific notes

- Requires the devise.cr I18n patch: boot-time YAML registration, lazy
  parsing, ruby-I18n nil semantics (a key with a nil value means
  "Translation missing", no en fallback; en fallback only for fully
  absent keys — a protected deviation of the devise port).

## Testing

```sh
make spec   # 80 examples
```

Oracle: `ruby oracle/cases.rb > oracle/expected.yml` (i18n 1.15.2) —
8825 lines covering every leaf of all 73 locales through
`Devise::I18n.translate`, plus integration cases (require registers the
dictionaries, `Devise.t` on ru/en, LocaleGenerator behavior). Mirror:
`spec/oracle_spec.cr`, 1:1.

## Updating dictionaries

Replace the gem in `oracle/vendor/`, copy `rails/locales/*.yml` to
`src/locales/`, re-record the oracle (`make oracle`), run `make spec`.
