# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2026_06_01_085153) do
  create_table "configs", charset: "utf8mb3", force: :cascade do |t|
    t.string "config", null: false
    t.string "config_value", null: false
    t.string "description", null: false
    t.binary "uuid", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "dashboard_stats", id: false, charset: "utf8mb3", force: :cascade do |t|
    t.string "name", null: false
    t.json "value", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "district_sites", charset: "utf8mb3", force: :cascade do |t|
    t.string "district_id", null: false
    t.string "site_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "districts", primary_key: "district_id", charset: "latin1", force: :cascade do |t|
    t.string "name", limit: 45, null: false
    t.bigint "region_id", null: false
    t.timestamp "created_at", default: -> { "CURRENT_TIMESTAMP" }
    t.timestamp "updated_at", default: -> { "CURRENT_TIMESTAMP" }
    t.index ["district_id"], name: "district_id_UNIQUE", unique: true
    t.index ["region_id"], name: "region_id_idx"
  end

  create_table "foot_prints", primary_key: "foot_print_id", charset: "utf8mb3", force: :cascade do |t|
    t.integer "user_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.binary "person_uuid", limit: 36
    t.integer "program_id", null: false
    t.integer "location_id", null: false
    t.boolean "synced", default: false
    t.binary "uuid", limit: 36, null: false
    t.datetime "encounter_datetime", precision: nil
    t.datetime "app_date_created", precision: nil
    t.datetime "app_date_updated", precision: nil
    t.index ["location_id", "created_at"], name: "index_foot_prints_on_location_id_and_created_at"
    t.index ["location_id", "person_uuid"], name: "index_foot_prints_on_location_id_and_person_uuid"
    t.index ["location_id"], name: "index_foot_prints_on_location_id"
  end

  create_table "location_npids", charset: "utf8mb3", force: :cascade do |t|
    t.integer "location_id"
    t.string "npid"
    t.boolean "assigned", default: false, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "allocated", default: false
    t.index ["assigned", "location_id"], name: "index_location_npids_on_assigned_and_location_id"
    t.index ["location_id", "updated_at"], name: "index_location_npids_on_location_id_and_updated_at"
    t.index ["location_id"], name: "index_location_npids_on_location_id"
    t.index ["npid"], name: "index_location_npids_on_npid", unique: true
  end

  create_table "location_tag_maps", charset: "utf8mb3", force: :cascade do |t|
    t.string "couchdb_location_tag_id", null: false
    t.string "couchdb_location_id", null: false
    t.integer "location_id", null: false
    t.string "location_tag_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "location_tags", primary_key: "location_tag_id", charset: "utf8mb3", force: :cascade do |t|
    t.string "name"
    t.string "couchdb_location_tag_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "locations", primary_key: "location_id", charset: "utf8mb3", force: :cascade do |t|
    t.string "name", null: false
    t.string "couchdb_location_id"
    t.string "description"
    t.string "latitude"
    t.string "longitude"
    t.boolean "voided", default: false, null: false
    t.string "void_reason"
    t.string "couchdb_parentlocation_id"
    t.bigint "district_id"
    t.string "code"
    t.integer "creator", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "ip_address"
    t.integer "parent_location"
    t.bigint "partner_code"
    t.binary "b2c_orgunit", limit: 1
    t.integer "dhis2_code"
    t.text "short_name"
    t.bigint "site_type_id"
    t.bigint "network_connect_status"
    t.datetime "last_seen", precision: nil
    t.boolean "activated", default: false, null: false
    t.index ["activated"], name: "index_locations_on_activated"
    t.index ["district_id"], name: "district_id_idx"
    t.index ["ip_address"], name: "index_locations_on_ip_address", unique: true
  end

  create_table "mailer_districts", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "district_id", null: false
    t.bigint "mailer_id", null: false
    t.boolean "voided", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["district_id"], name: "fk_mailer_districts_district"
    t.index ["mailer_id"], name: "fk_rails_a93dcc2597"
  end

  create_table "mailer_locations", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "location_id"
    t.bigint "mailer_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["location_id"], name: "fk_rails_fa9988e9fd"
    t.index ["mailer_id"], name: "fk_rails_2777ab826f"
  end

  create_table "mailing_lists", charset: "utf8mb3", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.string "email"
    t.string "phone_number"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "role_id"
    t.boolean "deactivated", default: false
    t.index ["role_id"], name: "fk_rails_039a728037"
  end

  create_table "mailing_logs", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "location_id"
    t.string "notification_type"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "district_id"
    t.index ["district_id"], name: "fk_mailing_logs_district"
    t.index ["location_id"], name: "fk_rails_c1f219ee43"
  end

  create_table "movement_caches", primary_key: "person_uuid", id: { type: :string, limit: 36 }, charset: "utf8mb3", force: :cascade do |t|
    t.integer "sites_visited", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sites_visited"], name: "index_movement_caches_on_sites_visited"
  end

  create_table "npid_registration_ques", charset: "utf8mb3", force: :cascade do |t|
    t.string "couchdb_person_id", null: false
    t.boolean "assigned", default: false, null: false
    t.integer "creator", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "npids", charset: "utf8mb3", force: :cascade do |t|
    t.string "npid", null: false
    t.string "version_number", null: false
    t.boolean "assigned", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "people", primary_key: "person_id", charset: "utf8mb3", force: :cascade do |t|
    t.string "couchdb_person_id", null: false
    t.string "given_name", null: false
    t.string "middle_name"
    t.string "family_name", null: false
    t.string "gender", null: false
    t.date "birthdate", null: false
    t.boolean "birthdate_estimated", default: false, null: false
    t.boolean "died", default: false, null: false
    t.date "deathdate"
    t.boolean "deathdate_estimated", default: false
    t.boolean "voided", default: false, null: false
    t.string "void_reason"
    t.datetime "date_voided", precision: nil
    t.string "npid"
    t.integer "location_created_at", null: false
    t.integer "creator", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["couchdb_person_id"], name: "index_people_on_couchdb_person_id", unique: true
    t.index ["npid"], name: "index_people_on_npid", unique: true
  end

  create_table "person_attribute_types", primary_key: "person_attribute_type_id", charset: "utf8mb3", force: :cascade do |t|
    t.string "couchdb_person_attribute_type_id", null: false
    t.string "name", null: false
    t.boolean "voided", default: false, null: false
    t.string "void_reason"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "person_attributes", primary_key: "person_attribute_id", charset: "utf8mb3", force: :cascade do |t|
    t.string "couchdb_person_id", null: false
    t.integer "person_id", null: false
    t.string "couchdb_person_attribute_type_id", null: false
    t.integer "person_attribute_type_id", null: false
    t.string "couchdb_person_attribute_id", null: false
    t.string "value", null: false
    t.boolean "voided", default: false, null: false
    t.string "void_reason"
    t.datetime "date_voided", precision: nil
    t.integer "voided_by"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "person_details", charset: "utf8mb3", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "middle_name"
    t.date "birthdate"
    t.boolean "birthdate_estimated", default: false, null: false
    t.string "gender", limit: 1, null: false
    t.string "ancestry_district"
    t.string "ancestry_ta"
    t.string "ancestry_village"
    t.string "home_district"
    t.string "home_ta"
    t.string "home_village"
    t.string "npid", null: false
    t.binary "person_uuid", limit: 36, null: false
    t.datetime "date_registered", precision: nil, null: false
    t.datetime "last_edited", precision: nil, null: false
    t.integer "location_created_at", null: false
    t.integer "location_updated_at", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "creator"
    t.boolean "voided", default: false, null: false
    t.integer "voided_by"
    t.datetime "date_voided", precision: nil
    t.string "void_reason"
    t.string "first_name_soundex", null: false
    t.string "last_name_soundex", null: false
    t.string "national_id"
    t.string "provincia"
    t.string "distrito"
    t.string "bairro"
    t.string "localidade"
    t.string "ponto_de_referencia"
    t.index ["first_name_soundex", "last_name_soundex"], name: "index_person_details_on_first_name_soundex_and_last_name_soundex"
    t.index ["gender", "last_name", "first_name"], name: "index_person_details_on_gender_and_last_name_and_first_name"
    t.index ["national_id"], name: "index_person_details_on_national_id", unique: true
    t.index ["npid"], name: "index_person_details_on_npid", unique: true
    t.index ["person_uuid"], name: "index_person_details_on_person_uuid", unique: true
    t.index ["voided", "date_registered"], name: "index_person_details_on_voided_and_date_registered"
  end

  create_table "person_details_audits", charset: "utf8mb3", force: :cascade do |t|
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "middle_name"
    t.date "birthdate"
    t.boolean "birthdate_estimated", default: false, null: false
    t.string "gender", limit: 1, null: false
    t.string "ancestry_district"
    t.string "ancestry_ta"
    t.string "ancestry_village"
    t.string "home_district"
    t.string "home_ta"
    t.string "home_village"
    t.string "npid", null: false
    t.binary "person_uuid", null: false
    t.datetime "date_registered", precision: nil, null: false
    t.datetime "last_edited", precision: nil, null: false
    t.integer "location_created_at", null: false
    t.integer "location_updated_at", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "creator"
    t.boolean "voided", default: false, null: false
    t.integer "voided_by"
    t.datetime "date_voided", precision: nil
    t.string "void_reason"
    t.string "first_name_soundex", null: false
    t.string "last_name_soundex", null: false
    t.string "national_id"
    t.string "provincia"
    t.string "distrito"
    t.string "bairro"
    t.string "localidade"
    t.string "ponto_de_referencia"
  end

  create_table "person_identifier_types", charset: "utf8mb3", force: :cascade do |t|
    t.string "name"
    t.string "code"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "person_identifiers", charset: "utf8mb3", force: :cascade do |t|
    t.bigint "person_detail_id"
    t.bigint "person_identifier_type_id"
    t.string "identifier_value"
    t.boolean "voided", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "push_trackers", id: :integer, charset: "utf8mb3", force: :cascade do |t|
    t.integer "site_id", null: false
    t.bigint "push_seq", default: 0, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "push_type", null: false
    t.index ["site_id", "push_type"], name: "index_push_trackers_on_site_id_and_push_type"
  end

  create_table "region", primary_key: "region_id", charset: "latin1", force: :cascade do |t|
    t.string "name", limit: 45, null: false
    t.string "created_at", limit: 45
    t.string "updated_at", limit: 45
    t.index ["name"], name: "name_UNIQUE", unique: true
  end

  create_table "region_districts", charset: "utf8mb3", force: :cascade do |t|
    t.string "region_id", null: false
    t.string "district_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "regions", charset: "utf8mb3", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.integer "creator", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "roles", primary_key: "role_id", charset: "utf8mb3", force: :cascade do |t|
    t.string "couchdb_role_id"
    t.string "role", null: false
    t.string "description"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "sync_errors", charset: "utf8mb3", force: :cascade do |t|
    t.integer "site_id", null: false
    t.timestamp "incident_time", null: false
    t.string "error", null: false
    t.boolean "synced", default: false, null: false
    t.string "uuid", limit: 36, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "created_at"], name: "index_sync_errors_on_site_id_and_created_at"
    t.index ["uuid"], name: "index_sync_errors_on_uuid", unique: true
  end

  create_table "sync_errors_archive", charset: "utf8mb3", force: :cascade do |t|
    t.integer "site_id", null: false
    t.timestamp "incident_time", null: false
    t.string "error", null: false
    t.boolean "synced", default: false, null: false
    t.string "uuid", limit: 36, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["site_id", "created_at"], name: "index_sync_errors_on_site_id_and_created_at"
    t.index ["uuid"], name: "index_sync_errors_on_uuid", unique: true
  end

  create_table "sync_stats_caches", id: false, charset: "utf8mb3", force: :cascade do |t|
    t.string "name", null: false
    t.json "value", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_management_people", primary_key: "person_id", id: :integer, charset: "utf8mb3", force: :cascade do |t|
    t.string "national_id"
    t.string "first_name", null: false
    t.string "surname", null: false
    t.string "other_name"
    t.date "birthdate"
    t.string "sex", limit: 1
    t.integer "phone_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_management_privileges", charset: "utf8mb3", force: :cascade do |t|
    t.string "name", null: false
    t.text "description", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_management_user_privileges", primary_key: "user_privilege_id", id: :integer, charset: "utf8mb3", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "privilege_id", null: false
    t.boolean "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "fk_rails_89ccb77e15"
  end

  create_table "user_management_users", primary_key: "user_id", id: :integer, charset: "utf8mb3", force: :cascade do |t|
    t.string "username", null: false
    t.string "email"
    t.string "password"
    t.string "password_digest"
    t.integer "person_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "user_roles", charset: "utf8mb3", force: :cascade do |t|
    t.string "couchdb_user_id"
    t.string "couchdb_role_id"
    t.bigint "user_id", null: false
    t.bigint "role_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "role", null: false
    t.string "description"
    t.index ["role_id"], name: "role_id_idx"
    t.index ["user_id"], name: "user_id_idx"
  end

  create_table "users", primary_key: "user_id", charset: "utf8mb3", force: :cascade do |t|
    t.string "username", null: false
    t.string "email"
    t.string "password_digest", null: false
    t.string "voided", limit: 1, default: "0", null: false
    t.string "void_reason"
    t.integer "location_id", default: 0, null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "default_user", default: false, null: false
  end

  add_foreign_key "districts", "region", primary_key: "region_id", name: "region_id"
  add_foreign_key "locations", "districts", primary_key: "district_id", name: "district_id"
  add_foreign_key "mailer_districts", "districts", primary_key: "district_id", name: "fk_mailer_districts_district"
  add_foreign_key "mailer_districts", "mailing_lists", column: "mailer_id"
  add_foreign_key "mailer_locations", "locations", primary_key: "location_id"
  add_foreign_key "mailer_locations", "mailing_lists", column: "mailer_id"
  add_foreign_key "mailing_lists", "roles", primary_key: "role_id"
  add_foreign_key "mailing_logs", "districts", primary_key: "district_id", name: "fk_mailing_logs_district"
  add_foreign_key "mailing_logs", "locations", primary_key: "location_id"
  add_foreign_key "user_management_user_privileges", "user_management_users", column: "user_id", primary_key: "user_id"
  add_foreign_key "user_roles", "roles", primary_key: "role_id", name: "role_id"
  add_foreign_key "user_roles", "users", primary_key: "user_id", name: "user_id"
end
