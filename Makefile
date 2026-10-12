.PHONY: spec oracle
spec:
	crystal spec

# Переснять ожидаемый вывод с оригинального гема (i18n 1.15.2):
#   ruby oracle/cases.rb > oracle/expected.yml
oracle:
	ruby oracle/cases.rb > oracle/expected.yml
