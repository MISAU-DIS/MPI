class SyncError < ApplicationRecord
  ERROR_MAX_LENGTH = 255 # the `error` column is a varchar(255)

  before_create :generate_uuid
  before_validation { self.error = error.to_s.truncate(ERROR_MAX_LENGTH) if error.present? }

  validates :uuid, uniqueness: true

  belongs_to :location,
             foreign_key: :site_id,
             primary_key: :location_id,
             optional: true

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
