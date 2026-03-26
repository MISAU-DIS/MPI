class ChangeRegionTimestampsToDatetime < ActiveRecord::Migration[7.0]
  def up
    change_column :region, :created_at, :datetime
    change_column :region, :updated_at, :datetime
  end

  def down
    change_column :region, :created_at, :string
    change_column :region, :updated_at, :string
  end
end

