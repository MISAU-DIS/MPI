class AddMozAddressFieldsToPersonDetailsAudits < ActiveRecord::Migration[7.0]
  def change
    add_column :person_details_audits, :provincia, :string
    add_column :person_details_audits, :distrito, :string
    add_column :person_details_audits, :bairro, :string
    add_column :person_details_audits, :localidade, :string
    add_column :person_details_audits, :ponto_de_referencia, :string
  end
end
