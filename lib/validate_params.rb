module ValidateParams
  def self.add_person(params)
    missing_parameters = []
    missing_parameters << "given_name" if params[:given_name].blank?
    missing_parameters << "family_name" if params[:family_name].blank?
    missing_parameters << "gender" if params[:gender].blank?
    missing_parameters << "birthdate" if params[:birthdate].blank?
    missing_parameters << "birthdate_estimated" if params[:birthdate_estimated].nil?


    return [] if missing_parameters.blank?
    return {status: 400, message: "Missing the following parameters: #{missing_parameters.join(', ')}"}

  end

  def self.search_by_name_and_gender(params)
    missing_parameters = []
    missing_parameters << "given_name" if params[:given_name].blank?
    missing_parameters << "family_name" if params[:family_name].blank?
    missing_parameters << "gender" if params[:gender].blank?

    return [] if missing_parameters.blank?
    return {status: 400, message: "Missing the following parameters: #{missing_parameters.join(', ')}"}
  end

  def self.search_by_npid(params)
    missing_parameters = []
    missing_parameters << "npid" if params[:npid].blank?
    return [] if missing_parameters.blank?
    return {status: 400, message: "Missing the following parameters: #{missing_parameters.join(', ')}"}
  end

  def self.search_by_doc_id(params)
    missing_parameters = []
    missing_parameters << "doc_id" if params[:doc_id].blank?
    return [] if missing_parameters.blank?
    return {status: 400, message: "Missing the following parameters: #{missing_parameters.join(', ')}"}
  end

  def self.search_by_attributes(params)
    if params[:values].blank?
      return {status: 400, message: "Missing values"}
    end
    return []
  end

  def self.update_person(params)
    if params[:doc_id].blank?
      return {status: 400, message: "Missing doc_id"}
    end
    return []
  end

  def self.potential_duplicates(params)
    if params[:npid].blank?
      return {status: 400, message: "Missing npid"}
    end
    return []
  end

  def self.merge_people(params)
    missing_parameters = []
    missing_parameters << "primary_person_doc_id" if params[:primary_person_doc_id].blank?
    missing_parameters << "secondary_person_doc_id" if params[:secondary_person_doc_id].blank?

    return [] if missing_parameters.blank?
    return {status: 400, message: "Missing the following parameters: #{missing_parameters.join(', ')}"}
  end

end
