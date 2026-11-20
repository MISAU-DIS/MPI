require 'rest-client'

module DiagnosticsService
  TIMEOUT = 10
  NO_RECORDS_SEQ = 2**62

  def self.run
    checks = []
    location = sync_user_check(checks)
    checks << database_check
    checks << npid_stock_check(location)
    master_checks(location).each { |check| checks << check }

    {
      checked_at: Time.current.iso8601,
      location: location && { location_id: location.location_id, name: location.name, code: location.code },
      checks: checks
    }
  end

  def self.sync_user_check(checks)
    username = DDE_SYNC_CONFIG[:username]
    if username.blank? || DDE_SYNC_CONFIG[:host].blank?
      checks << result('sync_user', 'fail', 'sync_config_missing', "config/dde_sync.yml (#{Rails.env})")
      return nil
    end

    user = User.find_by_username(username)
    if user.nil?
      checks << result('sync_user', 'fail', 'sync_user_not_found', username)
      return nil
    end

    location = Location.find_by(location_id: user.location_id) if user.location_id.present?
    if location.nil?
      checks << result('sync_user', 'fail', 'sync_user_without_location', username)
      return nil
    end

    checks << result('sync_user', 'ok', nil, "#{username} → #{location.name}")
    location
  end

  def self.database_check
    PersonDetail.unscoped.limit(1).pluck(:id)
    result('database', 'ok')
  rescue StandardError => e
    result('database', 'fail', 'database_error', e.message)
  end

  def self.npid_stock_check(location)
    return result('npid_stock', 'skipped') if location.nil?

    unassigned = LocationNpid.where(location_id: location.location_id).count
    return result('npid_stock', 'fail', 'npid_stock_empty', '0') if unassigned.zero?

    result('npid_stock', 'ok', nil, unassigned.to_s)
  end

  def self.master_checks(location)
    keys = %w[master_reachable master_login master_source]
    return keys.map { |key| result(key, 'skipped') } if DDE_SYNC_CONFIG[:host].blank?

    base = master_base_url
    reachable = master_reachable_check(base)
    return [reachable] + keys.drop(1).map { |key| result(key, 'skipped') } unless reachable[:status] == 'ok'

    token, login = master_login_check(base)
    return [reachable, login, result('master_source', 'skipped')] if token.nil?

    [reachable, login, master_source_check(base, token, location)]
  end

  def self.master_reachable_check(base)
    request(:get, "#{base}/status")
    result('master_reachable', 'ok', nil, base)
  rescue RestClient::ExceptionWithResponse => e
    return result('master_reachable', 'ok', nil, "#{base} (HTTP #{e.http_code})") if e.http_code.to_i.between?(1, 499)

    failure('master_reachable', e, base)
  rescue StandardError => e
    failure('master_reachable', e, base)
  end

  def self.master_login_check(base)
    response = request(:post, "#{base}/login",
                       payload: { username: DDE_SYNC_CONFIG[:username], password: DDE_SYNC_CONFIG[:password],
                                  user_type: 'proxy' })
    token = JSON.parse(response.body)['access_token']
    return [nil, result('master_login', 'fail', 'unexpected_response', response.body.to_s.truncate(300))] if token.blank?

    [token, result('master_login', 'ok', nil, DDE_SYNC_CONFIG[:username])]
  rescue StandardError => e
    [nil, failure('master_login', e, DDE_SYNC_CONFIG[:username])]
  end

  def self.master_source_check(base, token, location)
    return result('master_source', 'skipped') if location.nil?

    request(:get, "#{base}/person_changes_new?site_id=#{location.location_id}&pull_seq=#{NO_RECORDS_SEQ}",
            headers: { Authorization: token })
    result('master_source', 'ok', nil, location.location_id.to_s)
  rescue StandardError => e
    failure('master_source', e, location.location_id.to_s)
  end

  def self.master_base_url
    port = DDE_SYNC_CONFIG[:port]
    host = port.nil? ? DDE_SYNC_CONFIG[:host] : "#{DDE_SYNC_CONFIG[:host]}:#{port}"
    "#{DDE_SYNC_CONFIG[:protocol]}://#{host}/v1"
  end

  def self.request(method, url, payload: nil, headers: {})
    RestClient::Request.execute(method: method, url: url, payload: payload, headers: headers,
                                open_timeout: TIMEOUT, read_timeout: TIMEOUT)
  end

  def self.failure(key, error, context)
    detail = [context, error.message]
    detail << error.response.body.to_s.truncate(300) if error.respond_to?(:response) && error.response.present?
    result(key, 'fail', MasterErrorClassifier.code(error), detail.compact.join(' · '))
  end

  def self.result(key, status, reason = nil, detail = nil)
    { key: key, status: status, reason: reason, detail: detail }
  end
end
