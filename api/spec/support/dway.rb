require 'sequel/core'

ENV['DRMDB_DATABASE_URL']        = 'postgres://localhost/drmdb_test'
ENV['SUBMITTER_DB_DATABASE_URL'] = 'postgres://localhost/submitter_db_test'
ENV['DRA_SSH_HOST']              = 'localhost'
ENV['DRA_SSH_USER']              = 'alice'
ENV['DRA_SSH_KEY_DATA']          = 'KEY_DATA'

RSpec.configure do |config|
  config.before :suite do
    Sequel.extension :migration

    Sequel.connect ENV.fetch('DRMDB_DATABASE_URL') do |db|
      Sequel::Migrator.run db, 'db/dway/drmdb/migrations'
    end

    Sequel.connect ENV.fetch('SUBMITTER_DB_DATABASE_URL') do |db|
      Sequel::Migrator.run db, 'db/dway/submitter_db/migrations'
    end
  end
end
