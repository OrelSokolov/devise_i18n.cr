# Oracle spec: порт воспроизводит oracle/expected.yml (снято с настоящего
# devise-i18n 1.16.1 + ruby-i18n 1.15.2 — oracle/cases.rb): все листья
# всех 73 локалей через Devise::I18n.translate, плюрализация count: 1/2,
# хелпер fix_model_name_case.
#
# Зеркальные правила (семантика ruby-I18n в терминах порта):
#   * nil-лист → "Translation missing: <loc>.<path>";
#   * у plural-узла нет подключа one/other (other-only локали: ja/ko/…)
#     → "raise:I18n::InvalidPluralizationData";
#   * подключ есть, но значение nil → "nil".

require "spec"
require "../src/devise_i18n_cr"

EXPECTED = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/expected.yml").each_line do |line|
    if line.includes?('\t')
      id, value = line.split('\t', 2)
      hash[id] = value.chomp
    end
  end
  hash
end

PLURAL_KEYS = ["zero", "one", "two", "few", "many", "other"]

def i18n_escape(s : String) : String
  s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

alias SLeaf = String | Nil | Hash(String, SLeaf)

# YAML → дерево с сохранением nil (как Devise::I18n.convert).
def s_convert(raw) : SLeaf
  node = raw.is_a?(YAML::Any) ? raw.raw : raw
  case node
  when Hash
    h = {} of String => SLeaf
    node.each { |k, v| h[k.to_s] = s_convert(v) }
    h
  when Nil
    nil
  else
    node.to_s
  end
end

# Тот же обход, что в oracle/cases.rb: plural-узел (все ключи ∈
# PLURAL_KEYS) записывается целиком + подключи обходятся dot-путём.
record Leaf, path : String, value : SLeaf

def s_walk(node : SLeaf, prefix : String, acc : Array(Leaf)) : Nil
  case node
  when Hash
    unless node.empty? || node.keys.any? { |k| !PLURAL_KEYS.includes?(k) }
      acc << Leaf.new(prefix, node)
    end
    node.keys.sort.each do |k|
      s_walk(node[k], prefix.empty? ? k : "#{prefix}.#{k}", acc)
    end
  else
    acc << Leaf.new(prefix, node)
  end
end

def interp_vars(str : String) : Array(String)
  str.scan(/%{(\w+)}/).map(&.[](1)).uniq
end

def leaves_for(loc : String) : Array(Leaf)
  tree = s_convert(YAML.parse(DeviseI18n::LOCALES[loc]).raw).as(Hash(String, SLeaf))[loc]
  acc = [] of Leaf
  s_walk(tree, "", acc)
  acc.sort_by!(&.path)
end

def run_case(id : String) : String
  expected = EXPECTED[id]? || raise "no expected case: #{id}"
  actual = yield
  "#{expected == actual ? "" : "MISMATCH #{id}\n  expected: #{expected.inspect}\n  actual:   #{actual.inspect}\n"}"
end

ACTUAL_IDS = [] of String

def track(id : String) : String
  ACTUAL_IDS << id
  id
end

describe "devise-i18n oracle" do
  it "locale list" do
    run_case("locales") { DeviseI18n::LOCALES.keys.sort.join(",") }.should be_empty
    ACTUAL_IDS << "locales"
  end

  it "available_locales" do
    run_case("available_locales") { Devise::I18n.loaded_locales.sort.join(",") }.should be_empty
    ACTUAL_IDS << "available_locales"
  end

  DeviseI18n::LOCALES.keys.sort.each do |loc|
    it loc do
      Devise.locale = loc
      report = String::Builder.new

      leaves_for(loc).each do |leaf|
        path, value = leaf.path, leaf.value
        case value
        when Hash
          [1, 2].each do |count|
            id = track("#{loc}.#{path}|count#{count}")
            pick = count == 1 ? "one" : "other"
            actual =
              if !value.has_key?(pick)
                "raise:I18n::InvalidPluralizationData"
              elsif value[pick].nil?
                "nil"
              else
                vars = [] of String
                value.each_value { |v| vars.concat(interp_vars(v)) if v.is_a?(String) }
                interp = vars.uniq.reject { |v| v == "count" }.map { |v| {v, v} }.to_h
                Devise::I18n.translate(path, nil, count, interp).try { |t| i18n_escape(t) } || "nil"
              end
            expected = EXPECTED[id]? || "MISSING CASE #{id}"
            report << "MISSING CASE #{id}\n" if EXPECTED[id]?.nil?
            report << "MISMATCH #{id}\n  expected: #{expected.inspect}\n  actual:   #{actual.inspect}\n" unless expected == actual
          end
        else
          id = track("#{loc}.#{path}|raw")
          actual =
            if value.nil?
              "Translation missing: #{loc}.#{path}"
            else
              vars = interp_vars(value)
              count = vars.includes?("count") ? 1 : nil
              interp = vars.reject { |v| v == "count" }.map { |v| {v, v} }.to_h
              t = Devise::I18n.translate(path, nil, count, interp)
              t.nil? ? "Translation missing: #{loc}.#{path}" : i18n_escape(t)
            end
          expected = EXPECTED[id]? || "MISSING CASE #{id}"
          report << "MISSING CASE #{id}\n" if EXPECTED[id]?.nil?
          report << "MISMATCH #{id}\n  expected: #{expected.inspect}\n  actual:   #{actual.inspect}\n" unless expected == actual
        end
      end

      report.to_s.should be_empty
    end
  end

  it "ViewHelpers#fix_model_name_case" do
    {"en", "de"}.each do |loc|
      Devise.locale = loc
      ACTUAL_IDS << "helper.fix_case.#{loc}" << "helper.noop.#{loc}"
      run_case("helper.fix_case.#{loc}") do
        DeviseI18n::ViewHelpers.fix_model_name_case("Hello World", "errors.messages.not_saved")
      end.should be_empty
      run_case("helper.noop.#{loc}") do
        DeviseI18n::ViewHelpers.fix_model_name_case("Hello World", "devise.sessions.signed_in")
      end.should be_empty
    end
  end

  it "covers every expected case" do
    ACTUAL_IDS.uniq!
    (ACTUAL_IDS - EXPECTED.keys).should be_empty
    (EXPECTED.keys - ACTUAL_IDS).should be_empty
  end
end

# Интеграционные кейсы вне line-протокола: сценарий "положил ru.yml —
# всё на русском" и генератор devise:i18n:locale.
describe "devise-i18n integration" do
  it "require = словари в общем сторе, Devise.t на русском" do
    Devise.locale = "ru"
    Devise.t("devise.sessions.new.sign_in").should eq("Войти")
    Devise.t("devise.shared.links.sign_up").should eq("Регистрация")
    Devise.t("devise.failure.invalid", authentication_keys: "Эл. почта")
      .should eq("Эл. почта или пароль неверны.")
    Devise.t("devise.registrations.edit.title", resource: "Пользователь")
      .should eq("Пользователь: изменение")
    Devise.locale = "en"
    Devise.t("devise.sessions.new.sign_in").should eq("Log in")
  end

  it "LocaleGenerator копирует словарь в config/locales" do
    Dir.tempdir.tap do |tmp|
      root = File.join(tmp, "gen#{Random.new.hex(4)}")
      DeviseI18n::LocaleGenerator.run(["ru", "-q"], root: root)
      dest = File.join(root, "config/locales/devise.views.ru.yml")
      File.exists?(dest).should be_true
      File.read(dest).should eq(DeviseI18n::LOCALES["ru"])
    end
  end

  it "LocaleGenerator rejects unknown locale" do
    expect_raises(Exception, "No such locale: xx") do
      DeviseI18n::LocaleGenerator.run(["xx", "-q"], root: Dir.tempdir)
    end
  end
end
