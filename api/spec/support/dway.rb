require 'sequel/core'

ENV['DRMDB_DATABASE_URL']       = 'postgres://localhost/drmdb_test'
ENV['SUBMITTERDB_DATABASE_URL'] = 'postgres://localhost/submitterdb_test'

RSpec.configure do |config|
  config.before :suite do
    Rails.application.load_tasks

    Rake.application['dway:db:migrate'].invoke
  end

  config.around do |example|
    Dway.submitterdb.transaction auto_savepoint: true do
      Dway.submitterdb.rollback_on_exit

      Dway.drmdb.transaction auto_savepoint: true do
        Dway.drmdb.rollback_on_exit

        example.call
      end
    end
  end
end
