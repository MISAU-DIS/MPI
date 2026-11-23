module MonitoringService
  DEFAULT_DAYS = 30
  MAX_DAYS = 365

  def self.report(days:, current_user: nil)
    days = days.to_i
    days = DEFAULT_DAYS unless days.between?(1, MAX_DAYS)
    location = own_location(current_user)

    {
      location: location_details(location),
      npids: npid_counts(location),
      assignments: assignments(location, days),
      sync: sync_details,
      push_queue: push_queue(location),
      on_hold: on_hold
    }
  end

  # Records in the sync waiting room (SyncHold): could not be applied or were rejected by the
  # master, and are retried every sync.
  def self.on_hold
    {
      total: SyncHold.count,
      pull: SyncHold.pulls.count,
      push: SyncHold.pushes.count,
      oldest_since: SyncHold.minimum(:first_failed_at)&.iso8601
    }
  end

  def self.own_location(current_user)
    sync_user = User.find_by_username(DDE_SYNC_CONFIG[:username]) if DDE_SYNC_CONFIG[:username].present?
    location_id = sync_user&.location_id || current_user&.location_id
    Location.find_by(location_id: location_id) if location_id.present?
  end

  def self.location_details(location)
    return nil if location.nil?

    { location_id: location.location_id, name: location.name, code: location.code,
      doc_id: location.couchdb_location_id }
  end

  def self.npid_counts(location)
    return nil if location.nil?

    unassigned = LocationNpid.where(location_id: location.location_id).count
    assigned = LocationNpid.unscoped.where(location_id: location.location_id, assigned: true).count

    { unassigned: unassigned, assigned: assigned, allocated: unassigned + assigned }
  end

  def self.assignments(location, days)
    return nil if location.nil?

    from = (days - 1).days.ago.to_date
    counts = LocationNpid.unscoped
                         .where(location_id: location.location_id, assigned: true)
                         .where('updated_at >= ?', from.beginning_of_day)
                         .group('DATE(updated_at)')
                         .count
                         .transform_keys(&:to_date)

    per_day = (from..Date.current).map { |date| { date: date.iso8601, count: counts[date] || 0 } }

    { days: days, total: per_day.sum { |d| d[:count] }, per_day: per_day }
  end

  def self.sync_details
    status = SyncStatus.first

    {
      last_success_at: status&.last_success_at&.iso8601,
      last_attempt_at: status&.last_attempt_at&.iso8601,
      last_attempt_ok: status&.last_attempt_ok,
      last_attempt_error: status&.last_attempt_error,
      last_attempt_error_code: status&.last_attempt_error_code,
      failing_since: status&.failing_since&.iso8601
    }
  end

  def self.push_queue(location)
    return nil if location.nil?

    push_seq_new = Config.find_by_config('push_seq_new')&.config_value.to_i
    push_seq_update = Config.find_by_config('push_seq_update')&.config_value.to_i

    new_records = PersonDetail.unscoped
                              .where('person_details.id > ? AND person_details.location_updated_at = ?',
                                     push_seq_new, location.location_id)
                              .count
    updates = PersonDetail.unscoped
                          .joins(:person_details_audit)
                          .where('person_details.location_updated_at = ? AND person_details_audits.id > ?',
                                 location.location_id, push_seq_update)
                          .count

    { new_records: new_records, updates: updates, total: new_records + updates }
  end
end
