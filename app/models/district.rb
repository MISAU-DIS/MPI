# app/models/district.rb
class District < ApplicationRecord
  self.table_name  = 'districts'
  self.primary_key = 'district_id'

  belongs_to :province, class_name: 'Province', foreign_key: 'region_id'
end
