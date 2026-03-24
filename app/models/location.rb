class Location < ApplicationRecord
  
  default_scope { where(voided: 0) }
  validates :ip_address, uniqueness: true, allow_nil: true, allow_blank: true
 
  def self.get_location_by_name(name)
    location = Location.find_by_name(name)
    return location
  end

  def total_npids
    sites = self.sites
    allocated = LocationNpid.where(["location_id in (?)", sites]).count
  end
  
  def assigned_npids
    sites = self.sites
    assigned = LocationNpid.where(["location_id in (?) and assigned = 1", sites]).count
  end

  def sites
    sites = DistrictSite.where(["district_id in (?)", self.location_id]).map(&:site_id)
  end

  def online?
    status        = "OFFLINE"
    last_updates  = ""
    npids     = LocationNpid.where(location_id: self.id)
    unless npids.blank?
      max_person = Person.where(location_created_at: self.id).select(["*, MAX(updated_at)"]).limit(1).first rescue nil
      update_in_person = max_person.updated_at rescue nil
      location_users  = User.where(location_id: self.id).map(&:user_id)
      max_footprint   = FootPrint.where(["user_id in (?)", location_users]).select(["*, max(updated_at)"]).limit(1).first
      update_in_footprint = max_footprint.updated_at rescue nil

      unless update_in_person.blank? && update_in_footprint.blank?
        last_updates  = update_in_person.to_date 
      
        if (Date.today.to_date == update_in_person.to_date)
          status        = "ONLINE"
        end
      
      end

      return status, last_updates
    end
    
    return status, last_updates
  end
  
end
