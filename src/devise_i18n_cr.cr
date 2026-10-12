# devise_i18n_cr — порт devise-i18n 1.16.1
#
# Оригинал — community-гем словарей для devise: rails/locales/*.yml (73
# локали, верхний ключ YAML = имя локали = стем файла), хелпер
# DeviseI18n::ViewHelpers и генератор `devise:i18n:locale`. В Rails-режиме
# railtie гема добавляет файлы в I18n.load_path при буте — здесь аналог:
# все словари запечены в бинарь compile-time (read_file) и
# регистрируются в Devise::I18n.register_yaml при require. Рантаймовых
# записей нет: парсинг словаря ленивый, при первом lookup локали.
#
# Использование: require "devise_i18n_cr"; Devise.locale = "ru".
# Оракул: oracle/cases.rb → oracle/expected.yml (зеркало — spec/).
#
# Отклонения от гема (наследие Devise::I18n порта devise.cr):
#   * плюрализация one/other (few/many читаются только явным dot-путём
#     "activerecord.models.user.few") — ruby-I18n без rails-i18n даёт то же;
#   * у other-only локалей (ja/ko/id/km) count: 1 отдаёт nil, а не
#     raise InvalidPluralizationData (в остальном совпадает байт-в-байт).

require "devise_cr"
require "file_utils"

module DeviseI18n
  VERSION = "1.16.1"

  # locale → сырой YAML (верхний ключ = имя локали), байт-идентично
  # rails/locales/*.yml гема 1.16.1.
  LOCALES = begin
    h = {} of String => String
    {% for file in `find #{__DIR__}/locales -name "*.yml" | sort`.split %}
      {% if !file.empty? %}
        h[{{ file.gsub(/.*\//, "").gsub(/\.yml$/, "") }}] = {{ read_file(file) }}
      {% end %}
    {% end %}
    h
  end

  # Регистрация всех словарей в общий стор (аналог добавления файлов в
  # I18n.load_path на инициализации railtie — гем грузит все локали,
  # когда config.i18n.available_locales не задан).
  def self.install : Nil
    LOCALES.each do |loc, yaml|
      Devise::I18n.register_yaml(loc, yaml)
    end
  end

  # ViewHelpers (lib/devise-i18n/view_helpers.rb): downcase для
  # errors.messages.not_saved, кроме :de — немецкие существительные
  # всегда с заглавной.
  module ViewHelpers
    def self.fix_model_name_case(text : String, i18n_key : String) : String
      return text.downcase if i18n_key == "errors.messages.not_saved" && Devise.locale != "de"
      text
    end
  end

  # `rails g devise:i18n:locale <name>` — копирует встроенный словарь
  # <name>.yml в config/locales/devise.views.<name>.yml (генератор
  # Devise::I18n::LocaleGenerator гема). Thor-строки как у
  # Devise::ViewsGenerator.
  class LocaleGenerator
    def self.run(argv : Array(String) = [] of String,
                 root : String = Dir.current) : Nil
      force = argv.any? { |a| {"-f", "--force"}.includes?(a) }
      quiet = argv.any? { |a| {"-q", "--quiet"}.includes?(a) }
      name = argv.reject { |a| a.starts_with?('-') }.first?
      raise "Usage: devise:i18n:locale <locale>" unless name
      yaml = DeviseI18n::LOCALES[name]?
      raise "No such locale: #{name} (available: #{DeviseI18n::LOCALES.keys.sort.join(",")})" unless yaml
      dest = File.join(root, "config", "locales", "devise.views.#{name}.yml")
      if File.exists?(dest) && !force
        puts "   identical  #{dest}" unless quiet
        return
      end
      FileUtils.mkdir_p(File.dirname(dest))
      File.write(dest, yaml)
      puts "      create  #{dest}" unless quiet
    end
  end
end

# Boot-time установка: require шарды = словари в общем сторе
# (до первого запроса; сама локаль выставляется приложением).
DeviseI18n.install
