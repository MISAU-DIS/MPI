class PersonDetail < ApplicationRecord
  default_scope { where(voided: false) }

  has_many :person_details_audit, foreign_key: :person_uuid, primary_key: :person_uuid
  has_many :person_identifiers
  validates :creator,:location_created_at,:person_uuid,:date_registered,:last_edited,:first_name,:last_name, presence: true
  validates :person_uuid, :npid, uniqueness: true
  validates :national_id, uniqueness: true, allow_blank: true
  validate :valid_national_id, if: -> { national_id.present? }

  before_save :format_national_id

  private

  # Convert national_id to uppercase before saving 
  def format_national_id
    self.national_id = national_id&.upcase
  end 
  
  # Custom validation for Malawi National ID
  def valid_national_id
    if national_id.match?(/[SIOLU]/i) 
      errors.add(:national_id, "cannot contain the letters 'S', 'I', 'O', 'L', or 'U' (case insensitive)")
    elsif national_id.length != 8 || !national_id.match?(/\A[A-Z0-9]{8}\z/)
      errors.add(:national_id, "must be exactly 8 alphanumeric characters")
    end
  end
end
 