config_path = Rails.root.join("config/dde_sync.yml")

if File.exist?(config_path) && File.readable?(config_path)
  raw = File.read(config_path)

  config = YAML.safe_load(
    ERB.new(raw).result,
    aliases: true
  ).with_indifferent_access

  DDE_SYNC_CONFIG = config[Rails.env].freeze
else
  Rails.logger.warn("DDE Sync config missing: #{config_path}")

  DDE_SYNC_CONFIG = {}.with_indifferent_access
end