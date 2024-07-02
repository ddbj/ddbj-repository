namespace :dway do
  namespace :db do
    desc 'Run migrations'
    task :migrate, [:version] do |t, args|
      require 'sequel/core'

      Sequel.extension :migration

      Sequel.connect ENV.fetch('DRMDB_DATABASE_URL') do |db|
        Sequel::Migrator.run db, 'db/dway/drmdb/migrations', target: args[:version]&.to_i
      end

      Sequel.connect ENV.fetch('SUBMITTER_DB_DATABASE_URL') do |db|
        Sequel::Migrator.run db, 'db/dway/submitter_db/migrations', target: args[:version]&.to_i
      end
    end
  end
end
