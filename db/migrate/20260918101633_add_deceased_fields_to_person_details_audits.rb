class AddDeceasedFieldsToPersonDetailsAudits < ActiveRecord::Migration[7.0]
  def change
    # PersonService#update_person / #void_person (and now #mark_person_deceased) all do
    # `audit_record = person.dup` followed by `PersonDetailsAudit.create!(audit_person)`.
    # That dup carries every attribute person_details has, so person_details_audits has
    # to mirror its columns 1:1 or those calls start raising
    # ActiveRecord::UnknownAttributeError the moment person_details gains a column this
    # table doesn't have.
    add_column :person_details_audits, :died, :boolean, default: false, null: false
    add_column :person_details_audits, :deathdate, :date
    add_column :person_details_audits, :deathdate_estimated, :boolean, default: false, null: false
  end
end
