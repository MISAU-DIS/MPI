class CreatePersonIdentifierTypes < ActiveRecord::Migration[7.0]
  def change
    create_table :person_identifier_types do |t|
      t.string :name
      t.string :code
      t.string :description

      t.timestamps
    end
  end
end
