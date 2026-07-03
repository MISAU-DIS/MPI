class AddDecimalIdToNpids < ActiveRecord::Migration[7.0]
  def change
    return unless ENV['MASTER'] == 'true'

    add_column :npids, :decimal_id, :integer, limit: 4, null: false, default: 0
  end
end
