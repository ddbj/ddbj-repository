namespace :dway do
  namespace :db do
    desc 'Run migrations'
    task :migrate, [:version] => :environment do |t, args|
      require 'sequel/core'

      Sequel.extension :migration

      version = args[:version]&.to_i

      Sequel::Migrator.run Dway.drmdb,        'db/dway/drmdb/migrations',        target: version
      Sequel::Migrator.run Dway.submitter_db, 'db/dway/submitter_db/migrations', target: version
    end
  end
end
