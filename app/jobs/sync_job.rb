require 'rest-client'
require 'yaml'

class SyncJob < ApplicationJob
  queue_as :sync

  def initialize(*_args)
    super()

    sync_configs = YAML.load(File.read("#{Rails.root}/config/database.yml"), aliases: true)[:dde_sync_config]

    @protocol = sync_configs[:protocol]
    @host = sync_configs[:host]
    @username = sync_configs[:username]
    @pwd = sync_configs[:password]
    @port  = sync_configs[:port]

    @base_url = if @port.nil?
                  "#{@protocol}://#{@host}/v1"
                else
                  "#{@protocol}://#{@host}:#{@port}/v1"
                end

    @user = User.find_by_username(@username)

    if @user.nil?
      Rails.logger.error "SyncJob Error: User not found for username: #{@username}"
      return
    end

    @location = @user['location_id'].to_i

    @token = ''
  end

  def perform(*_args)
    # Do something later
    start_syncing
  end

  def start_syncing
    if File.exist?('/tmp/dde_sync.lock')
      puts 'Another process running!'
      exit
    else
      FileUtils.touch '/tmp/dde_sync.lock'
    end
    begin
      clear_errors
      broadcast('Starting synchronization...', level: :info)
      authorize
      broadcast('Authorized successfully.', level: :success)

      pull_new_records
      broadcast('Pull new records.', level: :info)

      pull_updated_records
      broadcast('Pull updated records.', level: :info)

      push_records_new
      broadcast('Push new records.', level: :info)

      push_records_updates
      broadcast('Push updated records.', level: :info)

      push_footprints
      broadcast('Push footprints.', level: :info)

      pull_npids
      broadcast('Pull NPIDs.', level: :info)

      push_errors
      broadcast('Push sync errors.', level: :info)

      broadcast('Synchronization completed successfully!', level: :success)
    rescue StandardError => e
      log_error(e.message)
    ensure
      FileUtils.rm '/tmp/dde_sync.lock' if File.exist?('/tmp/dde_sync.lock')
    end
  end

  def authorize
    if File.exist?("#{Rails.root}/tmp/token.json")
      @token = JSON.parse(File.read("#{Rails.root}/tmp/token.json")).symbolize_keys[:token]
      return @token if token_valid(@token)

      @token = authenticate
      File.write("#{Rails.root}/tmp/token.json", { token: @token }.to_json)

    else
      @token = authenticate
      File.write("#{Rails.root}/tmp/token.json", { token: @token }.to_json)
    end
  end

  def authenticate
    url = "#{@base_url}/login?username=#{@username}&password=#{@pwd}&user_type=proxy"

    JSON.parse(RestClient.post(url, {}))['access_token']
  end

  def token_valid(token)
    url = "#{@base_url}/verify_token"

    begin
      response = RestClient.post(url, { 'token' => token }.to_json, { content_type: :json, accept: :json })
    rescue StandardError
      return false
    end

    return true if response.code == 200

    false
  end

  def pull_new_records
    pull_seq = Config.find_by_config('pull_seq_new')['config_value'].to_i
    url = "#{@base_url}/person_changes_new?site_id=#{@location}&pull_seq=#{pull_seq}"
    begin
      updates = JSON.parse(RestClient.get(url, { Authorization: @token }))

      updates.each do |record|
        person = PersonDetail.unscoped.find_by(person_uuid: record['person_uuid'])
        pull_seq = record['id'].to_i
        person_identifiers = record.delete('person_identifiers')
        record.delete('id')
        record.delete('created_at')
        record.delete('updated_at')
        ActiveRecord::Base.transaction do
          if person.blank?
            if PersonDetail.exists?(npid: record['npid'])
              log_error("Duplicate NPID detected (#{record['npid']}) for incoming UUID #{record['person_uuid']}")
              next
            elsif PersonDetail.exists?(national_id: record['national_id']) && record['national_id'].present?
              log_error("Duplicate National ID detected (#{record['national_id']}) \
                for incomming UUID: #{record['person_uuid']}, national_id: #{record['national_id']}")
              next
            end
            person = PersonDetail.create!(record)
          else
            person.update(record)
            audit_record = JSON.parse(person.to_json)
            audit_record.delete('id')
            audit_record.delete('created_at')
            audit_record.delete('updated_at')
            PersonDetailsAudit.create!(audit_record)
          end
          PersonIdentifierService.sync(person, person_identifiers)
          Config.where(config: 'pull_seq_new').update(config_value: pull_seq)
        end
      end
    rescue StandardError => e
      log_error(e.message)
    end
  end

  def pull_updated_records
    pull_seq = Config.find_by_config('pull_seq_update')['config_value'].to_i
    url = "#{@base_url}/person_changes_updates?site_id=#{@location}&pull_seq=#{pull_seq}"

    begin
      updates = JSON.parse(RestClient.get(url, { Authorization: @token }))

      updates.each do |record|
        person = PersonDetail.unscoped.find_by(person_uuid: record['person_uuid'])
        pull_seq = record['update_seq'].to_i
        person_identifiers = record.delete('person_identifiers')
        record.delete('id')
        record.delete('created_at')
        record.delete('updated_at')
        record.delete('update_seq')
        ActiveRecord::Base.transaction do
          if person.blank?
            if PersonDetail.exists?(npid: record['npid'])
              log_error("Duplicate NPID detected (#{record['npid']}) for incoming UUID #{record['person_uuid']}")
              next
            elsif PersonDetail.exists?(national_id: record['national_id']) && record['national_id'].present?
              log_error("Duplicate National ID detected (#{record['national_id']}) \
                for incomming UUID: #{record['person_uuid']}, national_id: #{record['national_id']}")
              next
            end
            person = PersonDetail.create!(record)
          else
            person.update(record)
            audit_record = JSON.parse(person.to_json)
            audit_record.delete('id')
            audit_record.delete('created_at')
            audit_record.delete('updated_at')
            audit_record.delete('update_seq')
            PersonDetailsAudit.create!(audit_record)
          end
          PersonIdentifierService.sync(person, person_identifiers)
          Config.where(config: 'pull_seq_update').update(config_value: pull_seq)
        end
      end
    rescue StandardError => e
      log_error(e.message)
    end
  end

  def pull_npids
    npid_seq = Config.find_by_config('npid_seq')['config_value'].to_i
    url = "#{@base_url}/pull_npids?site_id=#{@location}&npid_seq=#{npid_seq}"

    begin
      npids = JSON.parse(RestClient.get(url, { Authorization: @token }))

      unless npids.blank?
        npids.each do |npid|
          if LocationNpid.unscoped.find_by_npid(npid['npid'])
            log_error("NPID seems to have already been assigned to a location: #{npid['npid']}")
            next
          end

          ActiveRecord::Base.transaction do
            LocationNpid.create!(location_id: npid['location_id'],
                                 npid: npid['npid'],
                                 assigned: npid['assigned'])
            Config.where(config: 'npid_seq').update(config_value: npid['id'])
          end
        end
      end
    rescue StandardError => e
      log_error(e.message)
    end
  end

  def push_records_new
    url = "#{@base_url}/push_changes_new"

    push_seq = Config.find_by_config('push_seq_new')['config_value'].to_i

    records_to_push = PersonDetail.unscoped.where('person_details.id > ? AND person_details.location_updated_at = ?',
                                                  push_seq, @location).order(:id).limit(100)

    # PUSH UPDATES
    records_to_push.each do |record|
      response = RestClient.post(url, format_payload(record), { Authorization: @token })
      redo if response.code != 201
      updated = Config.find_by_config('push_seq_new').update(config_value: record.id.to_i) if response.code == 201
      redo if updated != true
    rescue StandardError => e
      log_error(e.message)
    end
  end

  def push_records_updates
    url = "#{@base_url}/push_changes_updates"

    push_seq = Config.find_by_config('push_seq_update')['config_value'].to_i

    records_to_push = PersonDetail.unscoped.joins(:person_details_audit).where('person_details.location_updated_at = ?
        AND person_details_audits.id > ?', @location, push_seq).order('person_details_audits.id').limit(100).select('person_details.*,person_details_audits.id as update_seq')

    # PUSH UPDATES
    records_to_push.each do |record|
      response = RestClient.post(url, format_payload(record), { Authorization: @token })
      redo if response.code != 201
      if response.code == 201
        updated = Config.find_by_config('push_seq_update').update(config_value: record.update_seq.to_i)
      end
      redo if updated != true
    rescue StandardError => e
      log_error(e.message)
    end
  end

  def format_payload(person)
    {
      "id": person.id,
      "last_name": person.last_name,
      "first_name": person.first_name,
      "middle_name": person.middle_name,
      "gender": person.gender,
      "occupation": '',
      "cellphone_number": '',
      "home_village": person.home_village,
      "home_ta": person.home_ta,
      "home_district": person.home_district,
      "ancestry_village": person.ancestry_village,
      "ancestry_ta": person.ancestry_ta,
      "ancestry_district": person.ancestry_district,
      "provincia": person.provincia,
      "distrito": person.distrito,
      "bairro": person.bairro,
      "localidade": person.localidade,
      "ponto_de_referencia": person.ponto_de_referencia,
      "birthdate": person.birthdate,
      "birthdate_estimated": person.birthdate_estimated,
      "person_uuid": person.person_uuid,
      "npid": person.npid,
      "national_id": person.national_id,
      "date_registered": person.date_registered,
      "last_edited": person.last_edited,
      "location_created_at": person.location_created_at,
      "location_updated_at": person.location_updated_at,
      "creator": person.creator,
      "voided": person.voided,
      "voided_by": person.voided_by,
      "date_voided": person.date_voided,
      "void_reason": person.void_reason,
      "first_name_soundex": person.first_name_soundex,
      "last_name_soundex": person.last_name_soundex,
      "person_identifiers": PersonIdentifierService.for_person(person),
      "update_seq": begin
        person.update_seq
      rescue StandardError
        nil
      end
    }
  end

  def push_footprints
    url = "#{@base_url}/push_footprints"

    FootPrint.where(synced: false, location_id: @location).find_in_batches(batch_size: 50) do |batch|
      responses = Parallel.map(batch, in_threads: 10) do |foot|
        response = RestClient.post(url, foot.as_json, { Authorization: @token })
        foot.foot_print_id if response.code == 201 # Collect successful IDs
      rescue RestClient::ExceptionWithResponse => e
        Rails.logger.error("Failed to sync footprint #{foot.foot_print_id}: #{e.response}")
        log_error("#{e.message} #{foot.foot_print_id}: #{e.response}")
        nil
      rescue StandardError => e
        Rails.logger.error("Unexpected error syncing footprint #{foot.foot_print_id}: #{e.message}")
        log_error("#{e.message} #{foot.foot_print_id}: #{e.response}")
        nil
      end.compact

      # Bulk update successful records
      FootPrint.where(foot_print_id: responses).update_all(synced: true) if responses.any?
    end
  end

  def push_errors
    url = "#{@base_url}/push_errors"

    SyncError.where(synced: false).find_in_batches(batch_size: 500) do |batch|
      responses = Parallel.map(batch, in_threads: 10) do |error|
        response = RestClient.post(url, error.as_json, { Authorization: @token })
        error.id if response.code == 201 # Collect successful IDs
      rescue RestClient::ExceptionWithResponse => e
        Rails.logger.error("Failed to sync Error #{error.id}: #{e.response}")
        log_error("msg: #{e.message} error_id: #{error.id}: response: #{e.response}")
        nil
      rescue StandardError => e
        Rails.logger.error("Unexpected error syncing Error #{error.id}: #{e.message}")
        log_error("msg: #{e.message} error_id: #{error.id}: response: #{e.response}")
        nil
      end.compact

      # Bulk update successful records
      SyncError.where(id: responses).update_all(synced: true) if responses.any?
    end
  end

  def test_sync_flow
    authorize

    # Try pulling one record
    url = "#{@base_url}/person_changes_new?site_id=#{@location}&pull_seq=0&limit=1"
    JSON.parse(RestClient.get(url, { Authorization: @token }))

    updates = begin
      JSON.parse(response)
    rescue StandardError
      []
    end

    if updates.present?
      { status: 'success', message: 'Sync working: Able to fetch test record from remote server.' }
    else
      { status: 'warning',
        message: 'Connected and authenticated, but no records returned (pull working but no new data).' }
    end
  rescue RestClient::Exceptions::OpenTimeout, RestClient::Exceptions::ReadTimeout
    { status: 'failed', message: 'Sync failed: Connection timed out.' }
  rescue RestClient::ExceptionWithResponse => e
    { status: 'failed', message: "Sync failed at API layer: #{e.response}" }
  rescue StandardError => e
    { status: 'failed', message: "Unexpected Error: #{e.message}" }
  end

  private

  def log_error(error)
    return if @location_id.blank? || error.to_s.blank?

    existing_error = SyncError.find_by(site_id: @location_id, error: error.to_s)

    if existing_error
      existing_error.update!(
        incident_time: Time.now,
        updated_at: Time.now
      )
    else
      SyncError.create!(
        site_id: @location_id,
        incident_time: Time.now,
        error: error.to_s
      )
    end
  end

  def clear_errors
    ActiveRecord::Base.connection.execute('TRUNCATE TABLE sync_errors;')
  end

  def broadcast(message, level: :info)
    ActionCable.server.broadcast(
      'sync_channel',
      { message: message, level: level, timestamp: Time.now.strftime('%H:%M:%S') }
    )
  end
end
