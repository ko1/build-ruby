class ChangeTestStatusVisibilityDefault < ActiveRecord::Migration[7.0]
  def change
    change_column_default :test_statuses, :visible, from: 't', to: true
  end
end
