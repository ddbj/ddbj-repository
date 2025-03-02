class MakeUsersPermanent < ActiveRecord::Migration[7.1]
  def change
    change_column_null :requests,    :user_id, false
    change_column_null :submissions, :user_id, false
  end
end
