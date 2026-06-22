class DropNpidRegistrationQues < ActiveRecord::Migration[7.0]
  def change
    drop_table :npid_registration_ques
  end
end
