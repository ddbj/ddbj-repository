class DisallowNullOnValidationDetails < ActiveRecord::Migration[8.1]
  def change
    change_column_null :validation_details, :code, false
    change_column_null :validation_details, :severity, false
    change_column_null :validation_details, :message, false
  end
end
