# Psych 4 (shipped with Ruby 3.1+) requires classes to be explicitly
# permitted before safe_load/safe_dump will serialise them.
# The `audited` gem serialises ActiveRecord attribute changes — including
# date/time values — into the `audited_changes` YAML column, so we need
# to allowlist these common types.
Rails.application.config.active_record.yaml_column_permitted_classes = [
  Symbol,
  Date,
  Time,
  DateTime,
  BigDecimal,
  ActiveSupport::TimeWithZone,
  ActiveSupport::TimeZone,
  HashWithIndifferentAccess,
]
