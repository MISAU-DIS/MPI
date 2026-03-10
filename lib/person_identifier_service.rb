module PersonIdentifierService

  def self.create(person_detail, identifiers_params)
    return if identifiers_params.blank?

    identifiers_params.each do |identifier|
      type_code = identifier[:type]
      value     = identifier[:value]
      next if type_code.blank?

      identifier_type = PersonIdentifierType.find_by_code(type_code)
      next if identifier_type.blank?

      sem_documento = identifier_type.code == 'SEM_DOCUMENTO'
      next if !sem_documento && value.blank?

      next if PersonIdentifier.exists?(
        person_detail_id:          person_detail.id,
        person_identifier_type_id: identifier_type.id,
        voided:                    false
      )

      PersonIdentifier.create!(
        person_detail_id:          person_detail.id,
        person_identifier_type_id: identifier_type.id,
        identifier_value:          sem_documento ? nil : value,
        voided:                    false
      )
    end
  end

  def self.transfer(from_person, to_person)
    PersonIdentifier.active.where(person_detail_id: from_person.id).each do |ident|
      already_exists = PersonIdentifier.active.exists?(
        person_detail_id:          to_person.id,
        person_identifier_type_id: ident.person_identifier_type_id
      )
      ident.update(person_detail_id: to_person.id) unless already_exists
    end
  end

  def self.for_person(person_detail)
    PersonIdentifier.active
      .where(person_detail_id: person_detail.id)
      .includes(:person_identifier_type)
      .map do |ident|
        { type: ident.person_identifier_type.code, value: ident.identifier_value }
      end
  end

end
