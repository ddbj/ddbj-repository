namespace :dra do
  namespace :db do
    desc 'Run migrations'
    task :migrate, [:version] do |t, args|
      require 'sequel/core'

      Sequel.extension :migration

      Sequel.connect ENV.fetch('DRA_DATABASE_URL') do |db|
        Sequel::Migrator.run db, 'app/models/database/dra/db/migrations', target: args[:version]&.to_i
      end
    end
  end
end
