module LocationService
  def self.list_assigned_locations
    assigned_sites = LocationNpid.group("couchdb_location_id")
    locations = []

    (assigned_sites || []).each do |l|
      location = Location.find_by_couchdb_location_id(l.couchdb_location_id)
      location_tags = LocationTag.where("l.couchdb_location_id = ?",
                                        l.couchdb_location_id).joins("INNER JOIN location_tag_maps m
        ON m.location_tag_id = location_tags.location_tag_id
        INNER JOIN locations l ON l.location_id = m.location_id").select("location_tags.*")
      
      status, updated_on = location.online?
      
      locations << {
        name: location.name,
        doc_id: location.couchdb_location_id,
        latitude: location.latitude,
        longitude: location.longitude,
        code: location.code,
        location_tags: location_tags.map(&:name),
        host: location.ip_address,
        sync_status: status,
      }
    end

    return locations
  end

  def self.find_location(location_id)
    #status = 'OFFLINE'
  
    query = Location.where(couchdb_location_id: location_id)
    if query.blank?
      return {}
    end
    location = []
    (query || []).each do |l|
      location_tags = LocationTag.where("l.couchdb_location_id = ?",
                          l.couchdb_location_id).joins("INNER JOIN location_tag_maps m
        ON m.location_tag_id = location_tags.location_tag_id
        INNER JOIN locations l ON l.location_id = m.location_id").select("location_tags.*")
      #ds = DistrictSite.where(site_id: l.location_id).first #rescue "Unknown"
      #district = Location.find(ds.district_id).name rescue "Unknown"
      
      #rd = RegionDistrict.where(district_id: ds.district_id).first
      #region = Region.find(rd.region_id).name rescue "Unknown"
    
      #status, last_updated = l.online?

      location << {
        name: l.name,
        doc_id: l.couchdb_location_id,
        latitude: l.latitude,
        longitude: l.longitude,
        code: l.code,
        location_tags: location_tags.map(&:name),
       #district: district,
       #region: region,
        host: l.ip_address,
       #sync_status: status,
       #last_updated: last_updated
      }
    end
    return location
  end

  def self.get_locations(params)
    name = params[:name]

    # Build Location query
    if name.blank?
      query = Location.limit(10)
    else
      query = Location.where("name like (?)", "#{name}%")
    end

    page_size = (params[:page_size] or DEFAULT_PAGE_SIZE).to_i

    if params.has_key? :page
      offset = (params[:page] or 0).to_i * page_size
      query = query.offset(offset)
    end

    query = query.limit(page_size).order("name ASC")

    locations = []

    (query || []).each do |l|
      location_tags = LocationTag.where("l.couchdb_location_id = ?",
                                        l.couchdb_location_id).joins("INNER JOIN location_tag_maps m
        ON m.location_tag_id = location_tags.location_tag_id
        INNER JOIN locations l ON l.location_id = m.location_id").select("location_tags.*")
      
      npids     = LocationNpid.where(location_id: l.location_id)
      assigned  = LocationNpid.where(["location_id = ? and assigned = 1", l.location_id])

      #status, last_updated = l.online?

      locations << {
        location_id: l.location_id,
        name: l.name,
        doc_id: l.couchdb_location_id,
        latitude: l.latitude,
        longitude: l.longitude,
        code: l.code,
        location_tags: location_tags.map(&:name),
        host: l.ip_address,
        #sync_status: status,
        #last_updated: last_updated,
        allocated: npids.count,
        assigned: assigned.count,
      }
    end

    return locations
  end

  def self.location_sync_status(id)
    status        = "OFFLINE"
    last_updates  = ""
    npids     = LocationNpid.where(location_id: id)
    unless npids.blank?
      #last_updated_in_people = Person.where(location_created_at: id).select("MAX()")
      status        = "ONLINE"
      last_updates  = Date.today  
      return status, last_updates
    end
    
    return status, last_updates
  end
  
  def self.get_regions
    regions = []
    ( Region.all || [] ).each do |r|
      regions << {
        name: r.name,
        sites: r.sites,
        allocated: r.total_npids,
        assigned: r.assigned_npids
      }
    end
    
    return regions

  end

  def self.fetch_regional_stats
    @stats = {}
    ( Region.all || [] ).each do |r|
      region_name = r.name.downcase
      @stats["#{region_name}"] = {}
      
      ( r.districts || [] ).each do |d|
        district_sites = d.sites.count
        allocated_ids = d.total_npids
        assigned_ids = d.assigned_npids
        district = Location.where(location_id: d.id).first
        @stats["#{region_name}"]["#{district.name}"] = {}
        @stats["#{region_name}"]["#{district.name}"] = {
          sites: district_sites,
          allocated: allocated_ids,
          assigned: assigned_ids
        }

      end
    end
    return @stats
  end

  def self.sync_info
    user_ids = FootPrint.group(:user_id)
    user_ids_checked = [0]
    locations = {}
    
    (user_ids || []).each do |id|		
      data = ActiveRecord::Base.connection.select_one <<EOF
      Select distinct(user_id) user_id, max(created_at) created_at
      from foot_prints where user_id NOT IN(#{user_ids_checked.join(",")});
EOF

      location_id = self.get_locaton_id(data["user_id"].to_i) 
      next if location_id.blank?	
      
      if locations[location_id].blank?
	locations[location_id] = data["created_at"].to_time 
      end

      datetime = data["created_at"].to_time

      if locations[location_id] > datetime
        locations[location_id] = datetime
      end
     
      user_ids_checked << data["user_id"] .to_i	
    end

    sync_status = []
    (locations || []).each do |location_id, datetime|
      days = (Date.today - datetime.to_date).to_i
      location = Location.find(location_id)

      sync_status << {
        site_code: location.code,
        site_name: location.name,
        last_sync_datetime: datetime,
        last_sync_datetime_formated: datetime.strftime("%d/%b/%Y %H:%M:%S"),
	days_gone_since_last_sync: days,
        location_id: location.id 
      }
    end

    data = ActiveRecord::Base.connection.select_all <<EOF
    SELECT l.location_id, l.name, l.code FROM users u 
    INNER JOIN locations l ON l.location_id = u.location_id 
    WHERE user_id NOT IN(
      SELECT user_id FROM foot_prints GROUP BY user_id
    ) AND l.name NOT LIKE '%Baobab health%' GROUP BY u.location_id;
EOF

    (data || []).each do |u|
      location_id = u["location_id"].to_i
      available = false
      (sync_status || []).each do |s|
        if s[:location_id] == location_id
           available = true
        end
      end

      if !available
        sync_status << {
          site_code: u["code"],
          site_name: u["name"],
          last_sync_datetime: "N/A",
          last_sync_datetime_formated: "N/A",
	  days_gone_since_last_sync: 500,
          location_id: location_id 
        }
      end
    end	
    return sync_status
  end

  def self.whitelist_ip_address(location_id:, ip_address:)
    whitelisted = false
     location = Location.find_by(location_id: location_id)

      if location.nil?
        return { error: "Location with ID #{location_id} does not exist", whitelisted:}
      end

      if Location.exists?(ip_address: ip_address)
       return  { error: "IP address #{ip_address} is already whitelisted", whitelisted:}
      end

      location.update(ip_address: ip_address)

      { location: location, whitelisted: true }
  end

  private

  def self.get_locaton_id(user_id)
    return nil if user_id == 0
    user = User.find(user_id) 
    return nil if user.blank?
    return user.location_id
  end

  DEFAULT_PAGE_SIZE = 10
end
