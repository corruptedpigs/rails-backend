class CreateAudits < ActiveRecord::Migration[8.1]
  def self.up
    create_table :audits, force: :cascade do |t|
      t.belongs_to :auditable,  polymorphic: true, index: false
      t.belongs_to :associated, polymorphic: true, index: false
      t.belongs_to :user,       polymorphic: true, index: false

      t.string  :username
      t.string  :action
      t.text    :audited_changes
      t.integer :version,         default: 0
      t.string  :comment
      t.string  :remote_address
      t.string  :request_uuid

      t.datetime :created_at
    end

    add_index :audits, %i[auditable_type auditable_id version],
              name: "auditable_index"
    add_index :audits, %i[associated_type associated_id],
              name: "associated_index"
    add_index :audits, %i[user_id user_type],
              name: "user_index"
    add_index :audits, :request_uuid
    add_index :audits, :created_at
  end

  def self.down
    drop_table :audits
  end
end
