class PersonDetail < ApplicationRecord
  default_scope { where(voided: false) }

  has_many :person_details_audit, foreign_key: :person_uuid, primary_key: :person_uuid
  has_many :person_identifiers
  validates :creator, :location_created_at, :person_uuid, :date_registered, :last_edited, :first_name, :last_name, presence: true
  validates :person_uuid, :npid, uniqueness: true
  validates :national_id, uniqueness: true, allow_blank: true
  validate :valid_national_id, if: -> { national_id.present? }

  before_save :format_national_id

  private

  # Convert national_id to uppercase before saving 
  def format_national_id
    self.national_id = national_id&.upcase
  end 
  
  # Custom validation for Mozambique National ID (Bilhete de Identidade)
  def valid_national_id
    # Standard Mozambique BI format: 12 numeric digits followed by 1 uppercase letter
    unless national_id.match?(/\A\d{12}[A-Z]\z/)
      errors.add(:national_id, "must be a valid Mozambique BI format (exactly 12 digits followed by 1 letter)")
    end
  end
end