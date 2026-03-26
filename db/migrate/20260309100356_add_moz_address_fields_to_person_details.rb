class AddMozAddressFieldsToPersonDetails < ActiveRecord::Migration[7.0]
  def change
    add_column :person_details, :provincia, :string
    add_column :person_details, :distrito, :string
    add_column :person_details, :bairro, :string
    add_column :person_details, :localidade, :string
    add_column :person_details, :ponto_de_referencia, :string
  end
end
