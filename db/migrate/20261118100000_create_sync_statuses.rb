class CreateSyncStatuses < ActiveRecord::Migration[7.0]
  def change
    create_table :sync_statuses do |t|
      t.datetime :last_attempt_at
      t.boolean :last_attempt_ok
      t.text :last_attempt_error
      t.datetime :last_success_at
      t.datetime :failing_since
      t.timestamps
    end
  end
end
