require 'sequel/core'
require 'uri'

namespace :dway do
  namespace :db do
    env_keys = %w(DRMDB_DATABASE_URL SUBMITTERDB_DATABASE_URL BIOPROJECT_DATABASE_URL)

    desc 'Create databases'
    task :create do
      env_keys.each do |key|
        uri = URI.parse(ENV.fetch(key))

        sh "createdb #{uri.path.delete_prefix('/')}"
      end
    end

    desc 'Run migrations'
    task :migrate, [:version] => :environment do |t, args|
      Sequel.extension :migration

      version = args[:version]&.to_i

      Sequel::Migrator.run Dway.drmdb,       'db/dway/drmdb/migrations',       target: version
      Sequel::Migrator.run Dway.submitterdb, 'db/dway/submitterdb/migrations', target: version
      Sequel::Migrator.run Dway.bioproject,  'db/dway/bioproject/migrations',  target: version
    end

    desc 'Prepare databases'
    task :prepare => %i[create migrate]

    desc 'Drop databases'
    task :drop do
      env_keys.each do |key|
        uri = URI.parse(ENV.fetch(key))

        sh "dropdb --if-exists #{uri.path.delete_prefix('/')}"
      end
    end
  end
end
