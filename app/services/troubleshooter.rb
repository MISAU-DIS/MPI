require 'yaml'
require 'net/http'
require 'rest-client'
require 'uri'
require 'securerandom'

class Troubleshooter
  include NetworkHelper

  CONFIG_FILE_PATH = Rails.root.join('config', 'dde_sync.yml')
  LOCK_FILE_PATH = '/tmp/dde_sync.lock'

  def initialize
    @config = load_config
  end

  def select_solution(error_type)
    case error_type
    when 'unlock_sync_job'
      unlock_sync_job
    when 'resolve_sync_configs'
      resolve_sync_configs
    when 'detect_footprint_conflicts'
      detect_footprint_conflicts
    else
      { status: :unknown, message: 'Unknown error type' }
    end
  end

  def detect_footprint_conflicts
    footprint_summary = FootPrint.group(:location_id).count
    locations_with_footprints = footprint_summary.select { |_location_id, count| count > 0 }

    if locations_with_footprints.size > 1
      begin
        location = User.non_default_location! # this enforces one valid non-default user location
      rescue StandardError => e
        raise "<strong>Footprint Conflict:</strong> #{e.message}"
      end

      unless location
        raise '<strong>Unresolved Conflict:</strong> Found multiple locations but no valid non-default user location available.'
      end

      updated_records_count = FootPrint.update_all(location_id: location.location_id)
      unless updated_records_count.positive?
        raise "<strong>Update Failed:</strong> Could not reassign footprints for <strong>#{location.name}</strong>."
      end

      {
        status: :ok,
        message: "<strong>Footprints reassigned</strong> to <strong>#{location.name}</strong>.",
        details: {
          updated_records: updated_records_count,
          involved_locations: locations_with_footprints.keys
        }
      }

    else
      {
        status: :ok,
        message: '<strong>Footprints resolved successfully</strong> — all records belong to a single valid location.',
        details: locations_with_footprints
      }
    end
  end

  def unlock_sync_job
    if sync_job_running?
      { status: :ok, message: 'Sync is currently running' }
    elsif File.exist?(LOCK_FILE_PATH)
      File.delete(LOCK_FILE_PATH)
      { status: :ok, message: 'Removed sync lock file' }
    else
      { status: :ok, message: 'Sync lock already removed' }
    end
  end

  private

  # -----------------------------
  # Config helpers
  # -----------------------------
  def load_config
    # Pass through ERB to ensure ENV tags evaluate correctly in memory
    yaml_content = ERB.new(File.read(CONFIG_FILE_PATH)).result
    YAML.safe_load(yaml_content, aliases: true)
  end

  def get_sync_config
    # Returns the block matching the current Rails environment (e.g., development, production)
    @config[Rails.env] || @config[Rails.env.to_sym]
  end

  # -----------------------------
  # Environment-specific remote
  # -----------------------------
  def remote_host
    get_sync_config['host'] || get_sync_config[:host]
  end

  def remote_port
    get_sync_config['port'] || get_sync_config[:port]
  end

  def protocol
    get_sync_config['protocol'] || get_sync_config[:protocol]
  end

  def remote_base_url
    port = remote_port
    host = port.present? ? "#{remote_host}:#{port}" : remote_host
    "#{protocol}://#{host}/v1"
  end

  def local_base_url
    cfg = @config['dde_local_config'] || @config[:dde_local_config]
    
    if cfg.present?
      "#{cfg['protocol'] || cfg[:protocol]}://#{cfg['host'] || cfg[:host]}:#{cfg['port'] || cfg[:port]}/v1"
    else
      # Safe fallback for Docker proxy environment
      "http://localhost:#{ENV.fetch('PORT', 3000)}/v1"
    end
  end

  # -----------------------------
  # Sync config resolution (Read-Only Health Check)
  # -----------------------------
  def resolve_sync_configs
    sync_config = get_sync_config
    return { status: :error, message: "Sync configuration not found for #{Rails.env} environment." } unless sync_config

    username  = sync_config[:username] || sync_config['username']
    password  = sync_config[:password] || sync_config['password']

    unless username && password
      return { status: :auth_failed, message: 'Sync credentials missing. Please verify DDE_SYNC_USER and DDE_SYNC_PASS environment variables.' }
    end

    # Perform Read-Only Authentication Tests
    remote_success = authenticate_remote(username, password)
    local_success  = authenticate_local(username, password)

    if remote_success && local_success
      { status: :ok, message: 'Sync authentication succeeded (proxy & master)' }
    else
      { 
        status: :auth_failed, 
        message: 'Authentication failed. Please verify your configured credentials and ensure the Master API is reachable.' 
      }
    end
  end

  # -----------------------------
  # Remote authentication
  # -----------------------------
  def authenticate_remote(username, password)
    url = "#{remote_base_url}/login?username=#{username}&password=#{password}"
    response = begin
      RestClient.post(url, {})
    rescue StandardError
      nil
    end
    response && response.code == 200
  end

  def authenticate_local(username, password)
    url = "#{local_base_url}/login?username=#{username}&password=#{password}"
    response = begin
      RestClient.post(url, {})
    rescue StandardError
      nil
    end
    response && response.code == 200
  end

  # -----------------------------
  # Sync job helpers
  # -----------------------------
  def sync_job_running?
    Sidekiq::Workers.new.any? do |_process_id, _thread_id, work|
      work['payload']['class'] == SyncJob
    end
  end
end