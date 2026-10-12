# devise_i18n.cr — порт devise-i18n

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Порт [heartcombo/devise-i18n](https://github.com/heartcombo/devise-i18n)
**1.16.1** на Crystal. Оригинал: `oracle/vendor/devise-i18n-1.16.1`
(gem unpack, зафиксирован).

## Что это

Community-словари для devise: 73 локали (`rails/locales/*.yml` —
байт-идентичные копии в `src/locales/`), хелпер `ViewHelpers` и
генератор `devise:i18n:locale`. В Rails railtie гема добавляет файлы в
`I18n.load_path` на буте; здесь все словари запечены в бинарь
compile-time (`read_file`) и регистрируются в `Devise::I18n.register_yaml`
при `require "devise_i18n_cr"` — рантаймовых записей нет, парсинг
словаря ленивый (при первом lookup локали).

Использование:

```crystal
require "devise_i18n_cr"
Devise.locale = "ru"
Devise.t("devise.sessions.new.sign_in") # => "Войти"
```

Требует патч devise.cr: `Devise::I18n.register_yaml` (boot-time
регистрация словаря), ленивый парсинг зарегистрированных локалей,
nil-семантика ruby-I18n (ключ со значением nil = "Translation missing",
без en-фоллбэка; фоллбэк на en остаётся только для полностью
отсутствующих ключей — это защищённая девиация порта devise).

## Статус

**Готово, зелёное**: 80 examples (`make spec`):
- `spec/oracle_spec.cr` — 8825 строк оракула
  (`ruby oracle/cases.rb > oracle/expected.yml`, i18n 1.15.2): все
  листья всех 73 локалей через `Devise::I18n.translate` с
  интерполяцией-заглушками, плюрализация `count: 1/2`, nil-ключи,
  списки локалей, `fix_model_name_case` (en/de) — 1:1;
- интеграционные кейсы: `require` = словари в общем сторе (`Devise.t`
  на русском/en), `LocaleGenerator` (копия в
  `config/locales/devise.views.<loc>.yml`, unknown locale → raise).

## API 1:1

- `DeviseI18n::LOCALES : Hash(String, String)` — локаль → сырой YAML
- `DeviseI18n.install` (вызывается при require)
- `DeviseI18n::ViewHelpers.fix_model_name_case(text, i18n_key)` —
  downcase для `errors.messages.not_saved`, кроме `:de`
- `DeviseI18n::LocaleGenerator.run(["ru", "-f", "-q"], root: ".")` —
  `rails g devise:i18n:locale ru`

## Отклонения от ruby (наследие Devise::I18n)

- плюрализация one/other: `few`/`many` читаются только явным dot-путём
  (`activerecord.models.user.few`) — ruby-I18n без rails-i18n даёт то же
  (плюрализационные proc-правила rails-i18n в YAML невозможны);
- other-only локали (ja/ko/id/km): `count: 1` → nil, ruby даёт
  `raise I18n::InvalidPluralizationData` (в оракуле отражено маркером);
- railtie-фильтр по `config.i18n.available_locales` не портирован —
  регистрируются все локали (соответствует пустому available_locales).

## Не портировано (нет потребителя)

- переведённые ERB-вьюхи (`app/views/devise/**` гема) и шаблоны
  `simple_form_for` — лягут в `Devise::ViewsGenerator` devise.cr, когда
  его вьюхи перейдут на `t(".key")`;
- `devise:i18n:views`-генератор.

## Обновление словарей

Заменить гем в `oracle/vendor/`, скопировать `rails/locales/*.yml` в
`src/locales/`, переснять оракул (`make oracle`), прогнать `make spec`.
