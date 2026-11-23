class PersonIdentifier < ApplicationRecord
  # PersonDetail's default scope hides voided people. Without lifting it here, the
  # "person detail must exist" check can't see a voided person, so a voided person's
  # documents could never be saved — and creating or pulling a voided person failed.
  belongs_to :person_detail, -> { unscope(where: :voided) }
  belongs_to :person_identifier_type

  scope :active, -> { where(voided: false) }
end
