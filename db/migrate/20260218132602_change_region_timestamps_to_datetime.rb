class ChangeRegionTimestampsToDatetime < ActiveRecord::Migration[7.0]
  def up
    change_column :regions, :created_at, :datetime
    change_column :regions, :updated_at, :datetime
  end

  def down
    change_column :regions, :created_at, :string
    change_column :regions, :updated_at, :string
  end
end

