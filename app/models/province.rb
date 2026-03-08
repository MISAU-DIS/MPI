class Province < ApplicationRecord
  self.table_name = 'region'
  self.primary_key = 'region_id'
end