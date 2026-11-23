require 'rest-client'
require 'yaml'

class SyncJob < ApplicationJob
  queue_as :sync

  def initialize(*_args)
    super()

    @protocol = DDE_SYNC_CONFIG[:protocol]
    @host     = DDE_SYNC_CONFIG[:host]
    @username = DDE_SYNC_CONFIG[:username]
    @pwd      = DDE_SYNC_CONFIG[:password]
    @port     = DDE_SYNC_CONFIG[:port]

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

  LOCK_FILE = '/tmp/dde_sync.lock'.freeze
  # A sync killed half-way (power cut, restart) leaves its lock behind. Without an expiry every
  # later sync would give up forever, so a lock older than this is treated as abandoned.
  LOCK_STALE_AFTER = 2.hours
  HOLD_RETRY_LIMIT = 200
  VOIDED_RESEND_CONFIG = 'resend_voided_people_v1'.freeze

  def start_syncing
    return unless acquire_lock

    attempted_at = Time.current
    @sync_failure = nil
    @sync_failure_code = nil
    begin
      clear_errors
      broadcast('Starting synchronization...', level: :info)
      authorize
      broadcast('Authorized successfully.', level: :success)

      pull_new_records
      broadcast('Pull new records.', level: :info)

      pull_updated_records
      broadcast('Pull updated records.', level: :info)

      retry_pull_holds
      queue_voided_resend_once
      retry_push_holds
      broadcast('Retried records on hold.', level: :info)

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

      if @sync_failure.nil?
        broadcast('Synchronization completed successfully!', level: :success)
      else
        broadcast("Synchronization finished with errors: #{@sync_failure}", level: :error)
      end
    rescue StandardError => e
      sync_failed(e)
      log_error(e.message)
    ensure
      record_sync_result(attempted_at)
      FileUtils.rm LOCK_FILE if File.exist?(LOCK_FILE)
    end
  end

  def acquire_lock
    if File.exist?(LOCK_FILE)
      if File.mtime(LOCK_FILE) > LOCK_STALE_AFTER.ago
        Rails.logger.info('SyncJob: another sync is running, skipping this run.')
        return false
      end

      Rails.logger.warn("SyncJob: removing a sync lock older than #{LOCK_STALE_AFTER.inspect} (abandoned sync).")
    end

    FileUtils.touch LOCK_FILE
    true
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
    pull_records('pull_new', 'pull_seq_new', 'person_changes_new', 'id')
  end

  def pull_updated_records
    pull_records('pull_update', 'pull_seq_update', 'person_changes_updates', 'update_seq')
  end

  # Fetching the batch can fail (network, master down): then nothing moves and the next sync tries
  # again. A record that can't be applied no longer stops the batch: it goes to the waiting room
  # (SyncHold) and the marker moves on, so one bad record can never block a site's pull.
  def pull_records(direction, seq_config, endpoint, seq_key)
    pull_seq = Config.find_by_config(seq_config)['config_value'].to_i
    url = "#{@base_url}/#{endpoint}?site_id=#{@location}&pull_seq=#{pull_seq}"

    begin
      updates = JSON.parse(RestClient.get(url, { Authorization: @token }))
    rescue StandardError => e
      sync_failed(e)
      log_error(e.message)
      return
    end

    updates.each do |record|
      apply_or_hold_pulled_record(direction, record, record[seq_key].to_i)
      Config.where(config: seq_config).update(config_value: record[seq_key].to_i)
    end
  end

  def apply_or_hold_pulled_record(direction, record, seq)
    uuid = record['person_uuid']

    ActiveRecord::Base.transaction { apply_pulled_record(record.deep_dup) }
    # The person is now up to date: any older pulled version still on hold is obsolete.
    SyncHold.pulls.where(person_uuid: uuid).delete_all
    true
  rescue StandardError => e
    SyncHold.park!(direction, uuid, seq: seq, reason: e.message, payload: record)
    log_error("Pull on hold (uuid #{uuid}, npid #{record['npid']}): #{e.message}")
    false
  end

  def apply_pulled_record(record)
    person_identifiers = record.delete('person_identifiers')
    %w[id created_at updated_at update_seq].each { |key| record.delete(key) }

    person = PersonDetail.unscoped.find_by(person_uuid: record['person_uuid'])

    if person.blank?
      if PersonDetail.unscoped.exists?(npid: record['npid'])
        raise "Duplicate NPID detected (#{record['npid']}) for incoming UUID #{record['person_uuid']}"
      end
      if record['national_id'].present? && PersonDetail.unscoped.exists?(national_id: record['national_id'])
        raise "Duplicate National ID detected (#{record['national_id']}) for incoming UUID #{record['person_uuid']}"
      end

      person = PersonDetail.create!(record)
    else
      person.update!(record)
      audit_record = JSON.parse(person.to_json)
      %w[id created_at updated_at update_seq].each { |key| audit_record.delete(key) }
      PersonDetailsAudit.create!(audit_record)
    end

    PersonIdentifierService.sync(person, person_identifiers)
  end

  # Records parked by a pull are applied again from what the master sent. A newer version of the
  # same person that went through since would already have removed the hold.
  def retry_pull_holds
    SyncHold.pulls.order(:last_attempt_at).limit(HOLD_RETRY_LIMIT).each do |hold|
      record = hold.payload_hash
      next hold.destroy if record.blank?

      apply_or_hold_pulled_record(hold.direction, record, hold.seq)
    end
  end

  # Records the master rejected are pushed again with resend=true (the master would otherwise
  # skip them by its per-site tracker). Creations go first, so updates find their person.
  # A network or server error stops the retries; they continue next sync.
  def retry_push_holds
    holds = SyncHold.pushes
                    .order(Arel.sql("direction = 'push_update'"), :seq)
                    .limit(HOLD_RETRY_LIMIT)

    holds.each do |hold|
      person = PersonDetail.unscoped.find_by(person_uuid: hold.person_uuid)
      next hold.destroy if person.nil?

      endpoint = hold.direction == 'push_new' ? 'push_changes_new' : 'push_changes_updates'
      payload = format_payload(person).merge(resend: true)
      payload[:update_seq] = hold.seq if hold.direction == 'push_update'

      break unless push_one(endpoint, payload, hold.direction, person, "retry #{hold.direction}")
    end
  end

  # Once per proxy: people inactivated before their first push were rejected by masters older
  # than this fix ("Person detail must exist") and skipped for good. Queue every voided person
  # created here and already behind the push marker; the master creates the missing ones and
  # simply refreshes the others.
  def queue_voided_resend_once
    return if Config.exists?(config: VOIDED_RESEND_CONFIG)

    push_seq = Config.find_by_config('push_seq_new')['config_value'].to_i
    PersonDetail.unscoped
                .where(voided: true, location_created_at: @location)
                .where('id <= ?', push_seq)
                .find_each do |person|
      next if SyncHold.exists?(direction: 'push_new', person_uuid: person.person_uuid)

      SyncHold.park!('push_new', person.person_uuid, seq: person.id,
                     reason: 'One-time resend of an inactivated person (F1 fix)')
    end

    Config.create!(config: VOIDED_RESEND_CONFIG, config_value: Time.current.iso8601,
                   description: 'Voided people re-queued for push once (F1 sync fix)',
                   uuid: SecureRandom.uuid)
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
      sync_failed(e)
      log_error(e.message)
    end
  end

  def push_records_new
    push_seq = Config.find_by_config('push_seq_new')['config_value'].to_i

    records_to_push = PersonDetail.unscoped.where('person_details.id > ? AND person_details.location_updated_at = ?',
                                                  push_seq, @location).order(:id).limit(100)

    # The counter only moves past records the master dealt with. A temporary failure (network,
    # server error) stops the push so it is retried next sync. A rejection (422) goes to the
    # waiting room (SyncHold) and is retried every sync; the push carries on.
    records_to_push.each do |record|
      break unless push_one('push_changes_new', format_payload(record), 'push_new', record,
                            "person #{record.id}")

      Config.find_by_config('push_seq_new').update!(config_value: record.id.to_i)
    end
  end

  def push_records_updates
    pushed_new_up_to = Config.find_by_config('push_seq_new')['config_value'].to_i
    push_seq = Config.find_by_config('push_seq_update')['config_value'].to_i

    records_to_push = PersonDetail.unscoped.joins(:person_details_audit).where('person_details.location_updated_at = ?
        AND person_details_audits.id > ?', @location, push_seq).order('person_details_audits.id').limit(100).select('person_details.*,person_details_audits.id as update_seq')

    records_to_push.each do |record|
      # The person's creation hasn't been pushed yet (the new-records push stopped on a network
      # error or hit its batch limit). Sending the update now would only be rejected, so updates
      # wait here, in order, for the next sync.
      if record.id > pushed_new_up_to
        Rails.logger.info("SyncJob: update #{record.update_seq} waits for person #{record.id} to be pushed first.")
        break
      end

      break unless push_one('push_changes_updates', format_payload(record), 'push_update', record,
                            "update #{record.update_seq}")

      Config.find_by_config('push_seq_update').update!(config_value: record.update_seq.to_i)
    end
  end

  # Pushes one record. Returns true when the master dealt with it (accepted, or rejected and put
  # on hold) and false when the push has to stop (network or server error).
  def push_one(endpoint, payload, direction, person, label)
    what = "#{label} (uuid #{person.person_uuid}, npid #{person.npid})"
    response = RestClient.post("#{@base_url}/#{endpoint}", payload, { Authorization: @token })
    raise "Unexpected response #{response.code} pushing #{what}" unless response.code == 201

    SyncHold.release!(direction, person.person_uuid)
    true
  rescue RestClient::UnprocessableEntity => e
    SyncHold.park!(direction, person.person_uuid,
                   seq: direction == 'push_update' ? payload[:update_seq] || person.try(:update_seq) : person.id,
                   reason: [e.message, e.response&.body.presence].compact.join(': '))
    log_push_failure(e, what, held: true)
    true
  rescue StandardError => e
    sync_failed(e)
    log_push_failure(e, what)
    false
  end

  def log_push_failure(error, what, held: false)
    body = error.respond_to?(:response) ? error.response&.body : nil
    message = [error.message, body.presence].compact.join(': ')
    message = "#{what}: #{message}"
    Rails.logger.error("PUSH #{held ? 'ON HOLD' : 'STOPPED'} at #{message}")
    log_error(message)
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
      "reactivation_reason": person.reactivation_reason,
      "date_reactivated": person.date_reactivated,
      "reactivated_by": person.reactivated_by,
      "died": person.died,
      "deathdate": person.deathdate,
      "deathdate_estimated": person.deathdate_estimated,
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
        sync_failed(e)
        Rails.logger.error("Failed to sync footprint #{foot.foot_print_id}: #{e.response}")
        log_error("#{e.message} #{foot.foot_print_id}: #{e.response}")
        nil
      rescue StandardError => e
        sync_failed(e)
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
        sync_failed(e)
        Rails.logger.error("Failed to sync Error #{error.id}: #{e.response}")
        log_error("msg: #{e.message} error_id: #{error.id}: response: #{e.response}")
        nil
      rescue StandardError => e
        sync_failed(e)
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

  def sync_failed(error)
    return if error.is_a?(RestClient::UnprocessableEntity)

    @sync_failure_code ||= MasterErrorClassifier.code(error)
    @sync_failure ||= error.message
  end

  def record_sync_result(attempted_at)
    status = SyncStatus.current
    if @sync_failure.nil?
      status.record_success!(attempted_at)
    else
      status.record_failure!(attempted_at, @sync_failure, @sync_failure_code)
    end
  rescue StandardError => e
    Rails.logger.error("SyncJob could not record the sync result: #{e.message}")
  end

  def log_error(error)
    return if @location.blank? || error.to_s.blank?

    message = error.to_s.truncate(SyncError::ERROR_MAX_LENGTH)
    # An error not yet sent to the master is just refreshed. One already sent is logged again,
    # so the master also hears that it happened again.
    existing_error = SyncError.find_by(site_id: @location, error: message, synced: false)

    if existing_error
      existing_error.update!(incident_time: Time.now, updated_at: Time.now)
    else
      SyncError.create!(site_id: @location, incident_time: Time.now, error: message)
    end
  end

  # Errors used to be wiped (TRUNCATE) at the start of every sync, including the ones never sent
  # to the master. Now only errors already sent and older than a week are removed.
  def clear_errors
    SyncError.where(synced: true).where('updated_at < ?', 7.days.ago).delete_all
  end

  def broadcast(message, level: :info)
    ActionCable.server.broadcast(
      'sync_channel',
      { message: message, level: level, timestamp: Time.now.strftime('%H:%M:%S') }
    )
  end
end
