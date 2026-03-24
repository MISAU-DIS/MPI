require 'sidekiq/web'
require 'sidekiq/cron/web'

# Configure Sidekiq-specific session middleware
Sidekiq::Web.use ActionDispatch::Cookies
Sidekiq::Web.use ActionDispatch::Session::CookieStore, key: "_interslice_session"

Rails.application.routes.draw do
  get 'dashboard/index'
  mount UserManagement::Engine, at: '/v1' 
  mount Rswag::Ui::Engine => '/api-docs'
  mount Rswag::Api::Engine => '/api-docs'
  mount Sidekiq::Web => '/v1/sidekiq'

  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html

  namespace :api do
    namespace :v1 do
      resources :user
      resources :people
      resources :location
      resources :npid
      resources :merge
    end
  end

  post "v1/register", to: "api/v1/user#register"
  post "v1/login", to: "api/v1/user#login"
  post "v1/add_user", to: "api/v1/user#add_user"
  post "v1/verify_token/", to: "api/v1/user#verify_token"
  post "v1/update_password", to: "api/v1/user#update_password"

  #people controller routes
  post "v1/add_person", to: "api/v1/people_details#create"
  post "v1/search_by_name_and_gender", to: "api/v1/people_details#search_by_name_and_gender"
  post "v1/search_by_npid", to: "api/v1/people_details#search_by_npid"
  post "v1/search_by_doc_id", to: "api/v1/people_details#search_by_doc_id"
  post "v1/search_by_attributes", to: "api/v1/people#search_by_attributes"
  post "v1/potential_duplicates", to: "api/v1/people#potential_duplicates"
  post "v1/merge_people", to: "api/v1/people_details#merge_people"
  post "v1/assign_npid", to: "api/v1/people#assign_npid"
  post "v1/update_person/", to: "api/v1/people_details#update_person"
  delete "v1/void_person/:person_uuid", to: "api/v1/people_details#void"

  #npid controller routes
  post "v1/assign_npids", to: "api/v1/npid#assign_npids"
  get  "v1/allocate_npids", to: "api/v1/npid#allocate_npids"

  #location controller routes
  get "v1/locations", to: "api/v1/location#index"
  post "v1/find_location", to: "api/v1/location#find"
  post "v1/list_locations", to: "api/v1/location#list_assigned_locations"

  post "v1/npids_assigned", to: "api/v1/location#npids_assigned"
  post "v1/total_allocated_npids", to: "api/v1/location#total_allocated_npids"
  post "v1/get_locations", to: "api/v1/location#get_locations"
  post "v1/whitelist_ip_address", to: "api/v1/location#whitelist_ip_address"

  #footprint
  post "v1/update_footprint/", to: "api/v1/footprint#update_footprint"
  get  "/v1/sync_stats", to: "api/v1/footprint#stats"

  #merging
  post "v1/merge_people", to: "api/v1/merge#merge"
  post "v1/reassign_npid", to: "api/v1/people_details#reassign_npid"
  post "v1/rollback_merge", to: "api/v1/merge#rollback_merge"

  post "v1/search/people", to: "api/v1/people_match#get"
  get   "v1/get_regions", to: "api/v1/location#get_regions"
  get   "v1/get_regional_stats", to: "api/v1/location#regional_stats"
  post  "/v1/update_location_field", to: "api/v1/location#update_location_field"

  #dashboard links
  get   "v1/new_ids_assigned", to: "api/v1/people#total_assigned"
  get   "v1/foot_print_stats", to: "api/v1/people#client_movements"
  get   "v1/system_info", to: "api/v1/system#info"
  get   "v1/status",      to: "api/v1/status#index"
  get   "v1/cum_total_assigned", to: "api/v1/people#cum_total_assigned"
  get   "v1/sync_info", to: "api/v1/location#sync_info"
  get   "v1/footprints", to: "api/v1/footprint#by_category"

  get   "v1/new_registrations", to: "api/v1/dashboard#new_registrations"
  get   "v1/new_registrations_by_site", to: "api/v1/dashboard#new_registrations_by_site"
  get   'v1/new_reg_past_30', to: 'api/v1/dashboard#new_reg_past_30'
  get   'v1/client_movement', to: 'api/v1/dashboard#client_movement'
  get   'v1/npid_status', to: 'api/v1/dashboard#npid_status'
  get   'v1/connected_sites', to: 'api/v1/dashboard#connected_sites'
  get   'v1/site_activity', to: 'api/v1/dashboard#site_activity'
  get   'v1/location_npid_status', to: 'api/v1/dashboard#location_npid_status'
  get   'v1/refresh_dashboard', to: 'api/v1/dashboard#refresh_dashboard'
  get   'v1/npid_reservoir', to: 'api/v1/dashboard#npid_reservoir'

  #sync links
  get   'v1/person_changes_new', to: 'api/v1/sync#pull_updates_new'
  get   'v1/person_changes_updates', to: 'api/v1/sync#pull_updates'
  post  'v1/push_changes_new', to: 'api/v1/sync#pushed_updates_new'
  post  'v1/push_changes_updates', to: 'api/v1/sync#pushed_updates'
  post  'v1/push_footprints', to: 'api/v1/sync#pushed_footprints'
  get   'v1/pull_npids', to: 'api/v1/sync#pull_npids'
  post  'v1/push_errors', to: 'api/v1/sync#pushed_errors'
  get   'v1/sync_errors', to: 'api/v1/sync#sync_errors'

  #config routes
  put 'v1/configs', to: 'api/v1/configs#update'

  # config/routes.rb
  get 'v1/reports/:filename', to: 'api/v1/report#show', as: :report

  get 'v1/roles', to: 'api/v1/mailing_lists#roles'

  get 'v1/mailing_lists',  to: 'api/v1/mailing_lists#index'
  post 'v1/mailing_list', to: 'api/v1/mailing_lists#create'
  put 'v1/mailing_list/:id', to: 'api/v1/mailing_lists#update'
  delete 'v1/mailing_list/:id/deactivate', to: 'api/v1/mailing_lists#destroy'

  #root to: redirect('/api-docs/')

  root "api/v1/services#index"

  get "documentation", to: "api/v1/documentation#index"
  get "quick_links", to: "api/v1/quick_links#index"

  # Troubleshooting
  namespace :api do
    namespace :v1 do
      # Troubleshooting with resources
      resources :troubleshooting, only: [:index] do
        collection do
          post :troubleshoot
          post :reset_sync_credentials
          post :test_sync
        end
      end

      # Services with resources
      resources :services, only: [:index] do
        collection do
          get :manage_services, to: "services#manage"
        end
      end
    end
  end
  
end
