# The sync "waiting room": a record that could not be applied (pull) or was rejected by the
# master (push) is parked here instead of blocking the sync or being skipped forever.
# SyncJob retries every hold at the start of each sync and deletes it once it goes through.
#
# One hold per person and direction. A newer failure for the same person replaces the
# older one, so a retry never applies stale data over newer data.
class SyncHold < ApplicationRecord
  DIRECTIONS = %w[pull_new pull_update push_new push_update].freeze

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :person_uuid, presence: true

  scope :pulls, -> { where(direction: %w[pull_new pull_update]) }
  scope :pushes, -> { where(direction: %w[push_new push_update]) }

  def self.park!(direction, person_uuid, seq:, reason:, payload: nil)
    now = Time.current
    hold = find_or_initialize_by(direction: direction, person_uuid: person_uuid.to_s)
    hold.first_failed_at ||= now
    hold.attempts = hold.new_record? ? 1 : hold.attempts + 1
    hold.seq = seq
    hold.payload = payload.to_json unless payload.nil?
    hold.reason = reason.to_s.truncate(2000)
    hold.last_attempt_at = now
    hold.save!
    hold
  end

  def self.release!(direction, person_uuid)
    where(direction: direction, person_uuid: person_uuid.to_s).delete_all
  end

  def payload_hash
    payload.present? ? JSON.parse(payload) : nil
  end
end
