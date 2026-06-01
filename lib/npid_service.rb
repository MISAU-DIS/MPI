module NpidService

  def self.que(couchdb_person)
    NpidRegistrationQue.create(couchdb_person_id: couchdb_person.id, creator: User.current.id)
  end

  # Assign Npids to a Site/Location.
  # Takes the number of requested IDs and requesting user.
  def self.assign(number_of_ids, current_user, location = "")
    available_ids = Npid.where(assigned: false).limit(number_of_ids).distinct

    # EARLY EXIT: Prevent SQL crash and return a clear operational error
    if available_ids.blank?
      raise ActiveRecord::RecordNotFound, "No available NPIDs in the master pool. Please run the faker script or load new NPIDs."
    end

    location = current_user.location_id if location.blank?

    ActiveRecord::Base.transaction do
      # 1. Map the data safely
      records = available_ids.map do |npid|
        {
          location_id: location.to_i,
          npid: npid.npid,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      # 2. Safe bulk insert into location_npids
      LocationNpid.insert_all(records)

      # 3. Safe bulk update the npids table (ZERO-MIGRATION FIX: finding by npid instead of id)
      Npid.where(npid: available_ids.map(&:npid)).update_all(assigned: true, updated_at: Time.current)
    end

    return available_ids
  end

  #assigning individual npid to clients
  def self.assign_npid(person)
    # available_npid = LocationNpid.where(assigned: 0,
    #   location_id: User.current.location_id).limit(1).map{|i| i.npid}.sample rescue nil

    # unless available_npid.blank?
      ActiveRecord::Base.transaction do
        if LocationNpid.where(assigned: 0,location_id: User.current.location_id).limit(100).sample.update(assigned: 1)
          return true
        else
          return 'No free npids available for location'
        end
      end
    # end
  end

  #   Assign npid to a patient.
  def self.assign_id_person(person, user)
    ActiveRecord::Base.transaction do
      # Get DDE User couchdb location id.
      location_id = user.location_id

      # Get all unassigned npids for this site/location.
      npid = LocationNpid.where(["assigned = FALSE AND
        location_id =?",location_id]).limit(100).sample

      # Assign npid to a person if unassigned npids exists.
      unless npid.blank?
        npid  = npid.first

        # Assign npid to a mysql person.
        mysql_person = PersonDetail.find_by_person_id(person.id)
        mysql_person.update_attributes(npid: person.npid)

        # Update npid in the location npids table to assigned.
        # Both in MySQL and CouchDb.
        npid.update_attributes(assigned: true)

        # ############# Void National patient identifier if it exists
        # attribute_type = PersonAttributeType.find_by_name('National patient identifier')
        # attributes = PersonAttribute.where("person_id = ?
        #   AND person_attribute_type_id = ?", person.id, attribute_type.id)

        # (attributes || []).each do |a|
        #   couchdb_person_attribute = CouchdbPersonAttribute.find(a.couchdb_person_attribute_id)
        #   couchdb_person_attribute.update_attributes(voided: true, void_reason: "Given new npid: #{npid}")
        # end
        ###########################################################


      end
    end

    return person
  end

  def self.npids_assigned(params)

    location_doc_id = params[:location_doc_id]
    location_npids  = LocationNpid.where("couchdb_location_id = ? and
      assigned = true", location_doc_id)

    return {assigned_npid: location_npids.length}
  end

  def self.total_allocated_npids(params)

    location_doc_id = params[:location_doc_id]
    location_npids  = LocationNpid.where("couchdb_location_id = ?",
     location_doc_id)

    return {allocated_npids: location_npids.length}

  end

  def self.allocate_npids(location_id:, count:)
    ActiveRecord::Base.transaction do
      allocated_npids = LocationNpid.where(location_id: location_id)
                                    .order(Arel.sql("RAND()"))
                                    .limit(count)

      raise ActiveRecord::RecordNotFound, "No NPIDs available for allocation" if allocated_npids.blank?
      
      LocationNpid.where(id: allocated_npids.pluck(:id)).update_all(allocated: true)

      { npids: allocated_npids.map { |npid| npid.attributes.merge(allocated: true) } }
    end
  end
  
end