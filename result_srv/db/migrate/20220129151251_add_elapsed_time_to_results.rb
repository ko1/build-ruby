class AddElapsedTimeToResults < ActiveRecord::Migration[7.0]
  def change
    add_column :results, :elapsed_time, :float
  end
end
