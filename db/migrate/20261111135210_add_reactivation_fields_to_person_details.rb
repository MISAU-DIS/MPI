class AddReactivationFieldsToPersonDetails < ActiveRecord::Migration[7.0]
  def change
    add_column :person_details, :reactivation_reason, :string
    add_column :person_details, :date_reactivated, :datetime
    add_column :person_details, :reactivated_by, :integer
  end
end
