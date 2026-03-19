class Api::V1::PeopleDetailsController < ApplicationController
  before_action :set_api_v1_people_detail, only: [:show, :update, :destroy]



  # GET /api/v1/people_details
  def index
    @api_v1_people_details = Api::V1::PeopleDetail.all

    render json: @api_v1_people_details
  end

  # GET /api/v1/people_details/1
  def show
    render json: @api_v1_people_detail
  end

  # POST /api/v1/people_details
  def create

    errors = ValidateParams.add_person(params)
    if errors.blank?
      person = PersonService.create(params, current_user)
      render json: person, status: :ok
    else
      render json: errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/people_details/1
  def update_person
    errors = ValidateParams.update_person(params)
    if errors.blank?
      if PersonDetail.find_by_person_uuid(params[:doc_id]).blank?
        create
      else
        person = PersonService.update_person(params, current_user)
        render json: person
      end
    else
      render json: errors, status: :unprocessable_entity
    end
  end

 #Search by name and gender
 def search_person
    result = PersonService.search_person(params)
    set_pagination_headers(result)
    render json: result[:data], status: :ok
  end

 def search_by_name_and_gender
    errors = ValidateParams.search_by_name_and_gender(params)
    if errors.blank?
      result = PersonService.search_by_name_and_gender(params)
      set_pagination_headers(result)
      render json: result[:data], status: :ok
    else
      render json: errors, status: :unprocessable_entity
    end
  end

  def search_by_npid
   errors = ValidateParams.search_by_npid(params)
   if errors.blank?
     search_results = PersonService.search_by_npid(params)
     render json: search_results, status: :ok
   else
    render json: errors, status: :unprocessable_entity
   end
  end

   def search_by_doc_id
    errors = ValidateParams.search_by_doc_id(params)
    if errors.blank?
      search_results = PersonService.search_by_doc_id(params)
      render json: search_results, status: :ok
    else
      render json: errors, status: :unprocessable_entity
    end
  end

  def merge_people
    errors = ValidateParams.merge_people(params)
    if errors.blank?
      merge_results = MergeService.merge(params[:primary_person_doc_id], params[:secondary_person_doc_id],current_user)
      render json: merge_results, status: merge_results.blank? ? :not_found : :ok
    else
      render json: errors, status: :unprocessable_entity
    end
  end

  def reassign_npid
    person = PersonService.reassign_npid(params, current_user)
    render json: person
  end

  def void
    person = PersonService.void_person(void_params,current_user)
    unless person.blank?
      render json: person, status: :ok
    else
      render json: {error: 'Person not found'},  status: :not_found
    end
  end

  private
    def set_pagination_headers(result)
      response.set_header('X-Total-Count', result[:total])
      response.set_header('X-Page',        result[:page])
      response.set_header('X-Per-Page',    result[:per_page])
      response.set_header('X-Total-Pages', (result[:total].to_f / result[:per_page]).ceil)
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_api_v1_people_detail
      @api_v1_people_detail = Api::V1::PeopleDetail.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def api_v1_people_detail_params
      params.fetch(:api_v1_people_detail, {})
    end

    def void_params
      params.require(:void_reason)
      {person_uuid: params[:person_uuid], void_reason: params[:void_reason]}
    end
end
