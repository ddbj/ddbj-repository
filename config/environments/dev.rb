require 'active_support/core_ext/integer/time'

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = {'cache-control' => "public, max-age=#{1.year.to_i}"}

  # Store uploaded files on the local file system (see config/storage.yml for options).
  # config.active_storage.service = :local

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [:request_id]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  config.log_level = ENV.fetch('RAILS_LOG_LEVEL', 'info')

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = '/up'

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = {host: 'example.com'}

  # SMTP via mail1i — same as staging/production. dev は本番 D-way データを
  # 入れるため、メール送信先は実在 curator になり得る。Subject の `[Dev]`
  # prefix (ApplicationMailer) で誤認を防ぐ前提。
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address:             'mail1i',
    port:                465,
    tls:                 true,
    openssl_verify_mode: 'none'
  }

  # Enable locale fallbacks for I18n.
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  config.active_job.queue_adapter = :solid_queue
  config.active_storage.service   = :seaweedfs
  config.solid_queue.connects_to  = {database: {writing: :queue}}
end
