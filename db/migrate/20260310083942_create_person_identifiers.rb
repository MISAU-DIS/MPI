class CreatePersonIdentifiers < ActiveRecord::Migration[7.0]
  def change
    create_table :person_identifiers do |t|
      t.bigint :person_detail_id
      t.bigint :person_identifier_type_id
      t.string :identifier_value
      t.boolean :voided, default: false, null: false

      t.timestamps
    end
  end
end
