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

      %i(drmdb submitterdb bioproject).each do |name|
        db = Dway.public_send(name)
        db.create_schema 'mass', if_not_exists: true

        Sequel::Migrator.run db, "db/dway/#{name}/migrations", target: version
      end
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
