require "people_matching_service/bantu_soundex"
# require "people_matching_service/elasticsearch_person_dao"
# require "people_matching_service/dde_person_transformer"


module PersonService
  NPID_LENGTH = 6
  NATIONAL_ID_LENGTH = 8

  def self.reassign_npid(params, current_user)
    person = PersonDetail.find_by_person_uuid(params[:doc_id])
    #create if person.blank? #need to think about this one
    #Assign new NPID
    npid = LocationNpid.where(location_id: current_user.location_id, assigned: false).limit(100).sample

    audit_person = person.dup

    ActiveRecord::Base.transaction do
      person[:npid] = npid.npid
      person[:location_updated_at] = current_user.location_id
      person.save!
      audit_person = JSON.parse(audit_person.to_json)
      audit_person.delete('id')
      audit_person.delete('updated_at')
      PersonDetailsAudit.create!(audit_person)
      npid.update(assigned: true)
      person = JSON.parse(person.to_json)
      person.delete('id')
      person.delete('updated_at')
    end
    return self.get_person_obj(OpenStruct.new(person)) #OpenStruct to allow don notation
  end

  def self.assign_npid(params)
    couchdb_person = CouchdbPerson.find(params[:doc_id])
	return {} if couchdb_person.blank?

    NpidService.assign_npid(couchdb_person)  if couchdb_person.npid.blank?
    return self.get_person_obj(Person.find_by_couchdb_person_id(couchdb_person.id))
  end

  def self.create(params, current_user)
    location_npids = LocationNpid.where(["location_id = ?
      AND assigned = FALSE",current_user.location_id]).limit(100)
    
    raise UnprocessableEntityException, 'No NPIDs to assign' if location_npids.blank?

    npid                    = params[:npid] 
    given_name              = params[:given_name]
    family_name             = params[:family_name]
    middle_name             = params[:middle_name]
    gender                  = params[:gender]
    birthdate               = params[:birthdate]
    birthdate_estimated     = params[:birthdate_estimated]
    birthdate_estimated = false if birthdate_estimated.blank?

    occupation              = params[:attributes][:occupation] rescue nil
    cellphone_number        = params[:attributes][:cellphone_number] rescue nil

    current_district        = params[:attributes][:current_district] rescue nil
    current_ta              = params[:attributes][:current_traditional_authority] rescue nil
    current_village         = params[:attributes][:current_village] rescue nil

    ancestry_district           = params[:attributes][:home_district] rescue nil
    ancestry_ta                 = params[:attributes][:home_traditional_authority] rescue nil
    ancestry_village            = params[:attributes][:home_village] rescue nil

    art_number              = params[:identifiers][:art_number] rescue nil
    htn_number              = params[:identifiers][:htn_number] rescue nil
    national_id             = params.dig(:identifiers, :national_id).presence

  


    person = nil

    ActiveRecord::Base.transaction do

        if npid.present?
          npid = LocationNpid.unscoped.where("location_id = ?
            AND assigned = FALSE AND npid = ?  and allocated = ? ",
            current_user.location_id, npid, true).first
        else
          npid = location_npids.sample
        end
  
        uuid = params[:doc_id] || ActiveRecord::Base.connection.execute('SELECT uuid() as uuid').first[0]

        person = PersonDetail.create!(national_id: national_id,
                                      first_name: given_name,
                                      last_name: family_name,
                                      middle_name: middle_name,
                                      gender: gender,
                                      birthdate: birthdate,
                                      birthdate_estimated: birthdate_estimated,
                                      location_created_at: current_user.location_id,
                                      ancestry_district: ancestry_district,
                                      ancestry_ta: ancestry_ta,
                                      ancestry_village: ancestry_village,
                                      home_district: current_district,
                                      home_ta: current_ta,
                                      home_village: current_village,
                                      creator: current_user.id,
                                      location_updated_at: current_user.location_id,
                                      date_registered: Time.now,
                                      last_edited: Time.now,
                                      npid: npid.npid,
                                      person_uuid: uuid,
                                      first_name_soundex: given_name.soundex,
                                      last_name_soundex: family_name.soundex )

      #####################
      # NpidService.assign_npid(person)
      # #####################
      npid.update(assigned: true)
    end

    return self.after_create_get_person_obj(person, params[:attributes] || {})
  end

  def self.after_create_get_person_obj(person, params)

    person = {
      given_name:   person.first_name,
      family_name:  person.last_name,
      middle_name:  person.middle_name,
      gender: person.gender,
      birthdate:  person.birthdate,
      birthdate_estimated: person.birthdate_estimated,
      attributes: {
        occupation: params[:occupation],
        cellphone_number: params[:cellphone_number],
        current_district: params[:current_district],
        current_traditional_authority: params[:current_traditional_authority],
        current_village: params[:current_village],
        home_district: params[:home_district],
        home_traditional_authority: params[:home_traditional_authority],
        home_village: params[:home_village]
      },
      identifiers: {
        art_number: params[:art_number],
        htn_number: params[:htn_number],
        national_id:  person.national_id,
      },
      npid: person.npid,
      doc_id: person.person_uuid
    }

    # es_host, es_port = Rails.application.config.elasticsearch
    # es_client = ElasticsearchClient.new host: es_host, port: es_port
    # es_person_dao = ElasticsearchPersonDAO.new es_client
    # es_person_dao.save DDEPersonTransformer.transform(person)

    person
  end

  def self.update_person(params, current_user)
    doc_id = params[:doc_id]

    person = PersonDetail.find_by_person_uuid(doc_id)

    updated_person = {
                      first_name:            params[:given_name],
                      last_name:             params[:family_name],
                      middle_name:           params[:middle_name],
                      first_name_soundex:    params[:given_name].soundex,
                      last_name_soundex:     params[:family_name].soundex,
                      gender:                params[:gender],
                      birthdate:             params[:birthdate],
                      birthdate_estimated:   params[:birthdate_estimated],
                      person_uuid:           doc_id,
                      npid:                  person.npid,
                      national_id:           params.dig(:national_id) || person.national_id,

                      #occupation:            (params[:attributes][:occupation] rescue nil),
                      #cellphone_number:      (params[:attributes][:cellphone_number] rescue nil),
                      home_district:      (params[:attributes][:current_district] rescue nil),
                      home_ta:            (params[:attributes][:current_traditional_authority] rescue nil),
                      home_village:       (params[:attributes][:current_village] rescue nil),

                      ancestry_district:         (params[:attributes][:home_district] rescue nil),
                      ancestry_ta:               (params[:attributes][:home_traditional_authority] rescue nil),
                      ancestry_village:          (params[:attributes][:home_village] rescue nil),
                      location_created_at:  person.location_created_at,
                      location_updated_at:  current_user.location_id,
                      date_registered:      person.date_registered,
                      last_edited:          person.updated_at,
                      created_at:           person.created_at

                      #art_number:            (params[:identifiers][:art_number] rescue nil),
                      #htn_number:            (params[:identifiers][:htn_number] rescue nil)
                    }

    ActiveRecord::Base.transaction do
      audit_record = person.dup
      person.update(updated_person)
      audit_person = JSON.parse(audit_record.to_json)
      audit_person.delete('id')
      audit_person.delete('updated_at')
      PersonDetailsAudit.create!(audit_person)
    end
  end

  def self.potential_duplicates(params)
    npid = params[:npid]
    potential_duplicates = Person.where(npid: npid).having('COUNT(*) > 1')
    return potential_duplicates
  end

  def self.merge_people(params)
    primary_npid = params[:primary_npid]
    primary_doc_id = params[:primary_doc_id]

    secondary_npid = params[:secondary_npid]
    secondary_doc_id = params[:secondary_doc_id]

    if !primary_doc_id.blank?
      primary_person = Person.where(["npid =? AND doc_id =?", primary_npid, primary_doc_id]).last
    else
      primary_person = Person.where(["npid =?", primary_npid]).last
    end

    if !secondary_doc_id.blank?
      secondary_person = Person.where(["npid =? AND doc_id =?", secondary_npid, secondary_doc_id]).last
    else
      secondary_person = Person.where(["npid =?", secondary_npid]).last
    end

    ActiveRecord::Base.transaction do

    end

  end

  def self.get_person_obj(person, person_attributes = [])
    #This is an active record object
    if person_attributes.blank?
      return {
        given_name:   person.first_name,
        family_name:  person.last_name,
        middle_name:  person.middle_name,
        gender: person.gender,
        birthdate:  person.birthdate,
        birthdate_estimated: person.birthdate_estimated,
        location_updated_at: person.location_updated_at,
        last_edited: person.last_edited,
        attributes: {
          #occupation: self.get_attribute(person, "Occupation"),
          #cellphone_number: self.get_attribute(person, "Cell phone number"),
          current_district: person.home_district,
          current_traditional_authority: person.home_ta,
          current_village: person.home_village,
          home_district: person.ancestry_district,
          home_traditional_authority: person.ancestry_ta,
          home_village: person.ancestry_village
        },
          # identifiers: self.get_identifiers(person),
          npid: person.npid,
          national_id:  person.national_id,
          doc_id: person.person_uuid
        }
    else
      attributes = {}
      person_attributes.map do |a|
        puts a[:person_attribute_type_name]
        attributes["#{a[:person_attribute_type_name]}"] = a[:value]
      end

      return {
        given_name:   person.given_name,
        family_name:  person.family_name,
        middle_name:  person.middle_name,
        gender: person.gender,
        birthdate:  person.birthdate,
        birthdate_estimated: person.birthdate_estimated,
        attributes: {
          occupation: attributes["Occupation"],
          cellphone_number: attributes["Cell phone number"],
          current_district: attributes["Current district"],
          current_traditional_authority: attributes["Current traditional authority"],
          current_village: attributes["Current village"],
          home_district: attributes["Home district"],
          home_traditional_authority: attributes["Home traditional authority"],
          home_village: attributes["Home village"]
        },
          identifiers: self.get_identifiers(person),
          npid: (CouchdbPerson.find(person.couchdb_person_id).npid rescue nil),
          doc_id: person.couchdb_person_id
        }
    end
  end

  def self.get_attribute(person, type)
    person_attribute_type_id = PersonAttributeType.find_by_name(type).id
    person_attribute = PersonAttribute.where(["person_id =? AND person_attribute_type_id =?",
      person.person_id, person_attribute_type_id]).last
    #return person_attribute.blank? ? nil : person_attribute.value
    return person_attribute.blank? == true ? nil : person_attribute.value

  end

  def self.get_identifiers(person)
    attribute_types = ["National patient identifier", "HTN number", "ART number"]
    identifiers = []
    attribute_types.each do |attribute_type|
      identifier = self.get_attribute(person, attribute_type)
      unless identifier.blank?
        identifiers << {"#{attribute_type}": identifier}
      end
    end
    return identifiers
  end

  def self.search_by_name_and_gender(params)
    first_name  = params[:given_name]
    last_name = params[:family_name]
    gender      = params[:gender]

    people = PersonDetail.where(["first_name = ?
      AND last_name = ? AND gender = ?",
      first_name, last_name, gender]).limit(10)

    people_arr = []

    (people || []).each do |person|
      people_arr << self.get_person_obj(person)
    end

    return people_arr
  end

  def self.search_by_npid(params)
    npid = params[:npid]
    doc_id = params[:doc_id]

    unless doc_id.blank?
      person = PersonDetail.find_by_person_uuid(doc_id)
      unless person.blank?
        person_obj = self.get_person_obj(person)
        #FootPrintService.create(person)

        return [person_obj]
      end
    end

    people_arr = []

    unless npid.blank?
      #people = Person.where("npid = ? OR value = ?",
        #npid, npid).joins("RIGHT JOIN person_attributes p
      #ON p.couchdb_person_id = people.couchdb_person_id").select("people.*")
      people = []

      if npid.length == NPID_LENGTH
        # Fetch by npid
        person = PersonDetail.where(["npid =?", npid])
      elsif npid.length == NATIONAL_ID_LENGTH
        # Fetch by national_id
        person = PersonDetail.where(["national_id = ?", npid])
      end

      # PersonAttribute.where(["value =?", npid]).each do |person_attribute|
      #   people << Person.find(person_attribute.person_id)
      # end

      people = (person + people).uniq
      (people || []).each do |person|
        people_arr << self.get_person_obj(person)
      end

      if people_arr.length == 1
        #FootPrintService.create(people.first)
      end

    end

    return people_arr
  end

  def self.search_by_doc_id(params)
    doc_id = params[:doc_id]
    person = PersonDetail.where(person_uuid: doc_id)
    return [] if person.blank?
    #FootPrintService.create(person.first)
    return [self.get_person_obj(person.first)]
  end

  def self.search_by_attributes(params)
    values = params[:values]

    if !(values.is_a?(Array))
      values = []
    end

    if values.blank?
      values = []
    end

    people = Person.where(["value IN (?)", values]).joins("INNER JOIN person_attributes p
    ON p.couchdb_person_id = people.couchdb_person_id").select("people.*")

    people_arr = []

    (people || []).each do |person|
      people_arr << self.get_person_obj(person)
    end

    return people_arr
  end

  def self.total_assigned(date)
    data = Person.where("created_at BETWEEN ? AND ?",
      date.strftime("%Y-%m-%d 00:00:00"), date.strftime("%Y-%m-%d 23:59:59"))

    return data.count
  end

  def self.cum_total_assigned
    data = Person.where("npid IS NOT NULL AND (given_name NOT LIKE '%test%'
      AND family_name NOT LIKE '%test%') AND voided = 0")

    return data.count
  end

  def self.void_person(void_details,current_user)
    person = PersonDetail.unscoped.find_by_person_uuid(void_details[:person_uuid])
    return if person.blank?
    if person.voided == true
      return person
    else
      ActiveRecord::Base.transaction do
        audit_record = person.dup
        person.update(voided: true,
                      void_reason: void_details[:void_reason],
                      date_voided: Time.now,
                      voided_by: current_user.id)
        audit_person = JSON.parse(audit_record.to_json)
        audit_person.delete('id')
        audit_person.delete('updated_at')
        audit_person.delete('date_registered_date') if audit_person.has_key?('date_registered_date')
        puts audit_person
        PersonDetailsAudit.create!(audit_person)
      end
    end
    return person
  end

end

