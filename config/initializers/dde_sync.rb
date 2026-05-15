raw = File.read(Rails.root.join("config/dde_sync.yml"))
config = YAML.safe_load(ERB.new(raw).result, aliases: true).with_indifferent_access

DDE_SYNC_CONFIG = config[Rails.env].freeze
