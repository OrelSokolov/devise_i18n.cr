# Oracle cases for the devise-i18n port: the dictionary shipped by the gem
# (rails/locales/*.yml — 73 locales, gem 1.16.1) delivered into the I18n
# store, exercised through the real I18n.t API.
#
# Covered:
#   * locale file loading (railtie's I18n.load_path.concat equivalent:
#     I18n.backend.load_file per file)
#   * every leaf of every locale via I18n.t("<locale-dotted-path>"),
#     with dummy interpolation (%{var} => var name)
#   * plural nodes (one/few/many/other subkeys): dotted subkey dumps
#     + count: 1 / count: 2 behavior (plain I18n rule: 1 => :one,
#     else :other — "few"/"many" reachable only via dotted paths, same
#     limitation as the Crystal port's Devise::I18n)
#   * DeviseI18n::ViewHelpers#devise_i18n_fix_model_name_case (en/de)
#
# Run against the ORIGINAL gem (i18n 1.15.2):
#   ruby oracle/cases.rb > oracle/expected.yml
#
# Mirrored in spec/oracle_spec.cr. Line protocol: "<id>\t<value>".

VENDOR = File.expand_path("vendor/devise-i18n-1.16.1", __dir__)
LOCALES_DIR = File.join(VENDOR, "rails/locales")

def render(v)
  s = v.is_a?(String) ? v : v.inspect
  s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

gem "i18n", "= 1.15.2"
require "i18n"

FILES = Dir[File.join(LOCALES_DIR, "*.yml")].sort
PLURAL_KEYS = %w[zero one two few many other].freeze

# Railtie equivalent: I18n.load_path.concat(files) + lazy backend init
# on the first lookup.
I18n.load_path.concat(FILES)
I18n.reload!

# Deterministic (sorted) tree walk. A Hash whose keys are all plural
# subkeys is recorded as a plural node (for count cases) and its
# subkeys are also dumped as dotted leaves (the only way to reach
# few/many under plain I18n).
def walk(node, prefix, acc)
  if node.is_a?(Hash)
    if !node.empty? && node.keys.map(&:to_s).all? { |k| PLURAL_KEYS.include?(k) }
      acc << [prefix, node]
    end
    node.keys.sort.each do |k|
      walk(node[k], prefix.empty? ? k.to_s : "#{prefix}.#{k}", acc)
    end
  else
    acc << [prefix, node]
  end
end

LEAVES = {}
FILES.each do |f|
  loc = File.basename(f, ".yml")
  walk(YAML.load_file(f).fetch(loc), "", acc = [])
  LEAVES[loc] = acc.sort_by { |path, _| path }
end

case_run("locales") { LEAVES.keys.sort.join(",") }
case_run("available_locales") { I18n.available_locales.map(&:to_s).sort.join(",") }

# Interpolation vars of a leaf: %{name} => "name" (deterministic dummies).
# "count" is passed as count: 1 (Integer) so dotted plural-subkey lookups
# resolve to the String entry, not the parent Hash.
def interp_opts(str)
  opts = {}
  return opts if str.nil?
  str.scan(/%{(\w+)}/).flatten.uniq.each do |v|
    if v == "count"
      opts[:count] = 1
    else
      opts[v.to_sym] = v
    end
  end
  opts
end

LEAVES.each do |loc, leaves|
  leaves.each do |path, value|
    if value.is_a?(Hash)
      # count-driven plural behavior (one/other rule of plain I18n).
      # Dummies for the union of vars across subkeys so whichever subkey
      # the rule picks has all its interpolation vars present.
      vars = value.values.flat_map { |v| v.to_s.scan(/%{(\w+)}/) }.flatten.uniq - ["count"]
      opts = vars.map { |v| [v.to_sym, v] }.to_h
      case_run("#{loc}.#{path}|count1") { I18n.t(path, locale: loc, count: 1, **opts) }
      case_run("#{loc}.#{path}|count2") { I18n.t(path, locale: loc, count: 2, **opts) }
    else
      case_run("#{loc}.#{path}|raw") { I18n.t(path, locale: loc, **interp_opts(value)) }
    end
  end
end

# ViewHelpers#devise_i18n_fix_model_name_case (lib/devise-i18n/view_helpers.rb):
# downcase for errors.messages.not_saved unless locale is :de.
require File.join(VENDOR, "lib/devise-i18n/view_helpers")

[["en", "Hello World"], ["de", "Hello World"]].each do |loc, text|
  I18n.locale = loc
  helper = Object.new.extend(DeviseI18n::ViewHelpers)
  case_run("helper.fix_case.#{loc}") do
    helper.devise_i18n_fix_model_name_case(text, i18n_key: "errors.messages.not_saved")
  end
  case_run("helper.noop.#{loc}") do
    helper.devise_i18n_fix_model_name_case(text, i18n_key: "devise.sessions.signed_in")
  end
end
