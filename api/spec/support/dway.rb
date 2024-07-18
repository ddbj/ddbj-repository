require 'sequel/core'

RSpec.configure do |config|
  config.before :suite do
    Rails.application.load_tasks

    Rake.application['dway:db:migrate'].invoke
  end

  config.around do |example|
    Dway.bioproject.transaction auto_savepoint: true do
      Dway.bioproject.rollback_on_exit

      Dway.drmdb.transaction auto_savepoint: true do
        Dway.drmdb.rollback_on_exit

        Dway.submitterdb.transaction auto_savepoint: true do
          Dway.submitterdb.rollback_on_exit

          example.call
        end
      end
    end
  end
end
