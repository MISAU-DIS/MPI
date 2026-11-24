class CreateSyncHolds < ActiveRecord::Migration[7.0]
  def change
    create_table :sync_holds do |t|
      t.string :direction, null: false        # pull_new, pull_update, push_new, push_update
      t.string :person_uuid, limit: 36, null: false
      t.bigint :seq                           # pull: master's id/update_seq; push: local id/update_seq
      t.text :payload                         # pull only: the record as the master sent it (JSON)
      t.text :reason
      t.integer :attempts, null: false, default: 1
      t.datetime :first_failed_at, null: false
      t.datetime :last_attempt_at, null: false
      t.timestamps
    end

    add_index :sync_holds, %i[direction person_uuid], unique: true
  end
end
