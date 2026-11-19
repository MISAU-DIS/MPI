class SyncStatus < ApplicationRecord
  def self.current
    first || create!
  end

  def record_success!(attempted_at)
    update!(last_attempt_at: attempted_at, last_attempt_ok: true, last_attempt_error: nil,
            last_attempt_error_code: nil, last_success_at: Time.current, failing_since: nil)
  end

  def record_failure!(attempted_at, error, code = nil)
    update!(last_attempt_at: attempted_at, last_attempt_ok: false, last_attempt_error: error.to_s.truncate(1000),
            last_attempt_error_code: code, failing_since: failing_since || attempted_at)
  end
end
