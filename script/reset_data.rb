#!/usr/bin/env ruby

# Usage: bin/rails runner script/reset_data.rb
#
# users 以外のすべてのテーブルを TRUNCATE し、MinIO (ActiveStorage) のファイルをすべて削除する。

abort 'Do not run in production!' if Rails.env.production?

tables = ActiveRecord::Base.connection.tables - %w[users schema_migrations ar_internal_metadata]

ActiveRecord::Base.connection.execute "TRUNCATE #{tables.join(', ')} CASCADE"

puts "Truncated: #{tables.join(', ')}"

configs = Rails.configuration.active_storage.service_configurations
service = configs[Rails.configuration.active_storage.service.to_s]

if service && service['service'] == 'S3'
  bucket = service['bucket']

  client = Aws::S3::Client.new(
    endpoint:          service['endpoint'],
    access_key_id:     service['access_key_id'],
    secret_access_key: service['secret_access_key'],
    region:            service['region'],
    force_path_style:  true
  )

  deleted = 0

  client.list_objects_v2(bucket:).each do |page|
    objects = page.contents.map { {key: it.key} }

    next if objects.empty?

    client.delete_objects(bucket:, delete: {objects:})
    deleted += objects.size
  end

  puts "Deleted #{deleted} object(s) from MinIO bucket '#{bucket}'"
else
  puts 'ActiveStorage is not configured with S3/MinIO; skipping file deletion.'
end
