class PersonIdentifier < ApplicationRecord
  belongs_to :person_detail
  belongs_to :person_identifier_type

  scope :active, -> { where(voided: false) }
end
