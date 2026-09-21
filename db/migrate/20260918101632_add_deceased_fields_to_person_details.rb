class AddDeceasedFieldsToPersonDetails < ActiveRecord::Migration[7.0]
  def change
    add_column :person_details, :died, :boolean, default: false, null: false
    add_column :person_details, :deathdate, :date
    add_column :person_details, :deathdate_estimated, :boolean, default: false, null: false
  end
end
