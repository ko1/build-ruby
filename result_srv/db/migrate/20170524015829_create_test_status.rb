class CreateTestStatus < ActiveRecord::Migration[5.1]
  def change
    create_table :test_statuses do |t|
      t.string :name
      t.boolean :visible, default: true
      t.belongs_to :result
      t.time :timeout_notice
      t.string :alert_to
    end
  end
end
