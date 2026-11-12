class AddReactivationFieldsToPersonDetailsAudits < ActiveRecord::Migration[7.0]
  def change
    # PersonService#update_person / #void_person / #mark_person_deceased / #reactivate_person all do
    # `audit_record = person.dup` followed by `PersonDetailsAudit.create!(audit_person)`.
    # That dup carries every attribute person_details has, so person_details_audits has
    # to mirror its columns 1:1 or those calls start raising
    # ActiveRecord::UnknownAttributeError the moment person_details gains a column this
    # table doesn't have.
    add_column :person_details_audits, :reactivation_reason, :string
    add_column :person_details_audits, :date_reactivated, :datetime
    add_column :person_details_audits, :reactivated_by, :integer
  end
end
