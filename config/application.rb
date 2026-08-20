require_relative 'boot'
require_relative '../lib/middleware/path_scoped'

require 'rails'
# Pick the frameworks you want:
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'active_storage/engine'
require 'action_controller/railtie'
require 'action_mailer/railtie'
# require "action_mailbox/engine"
# require "action_text/engine"
require 'action_view/railtie'
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Repository
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    config.active_storage.variant_processor = :disabled
    config.time_zone                        = 'Asia/Tokyo'

    # Active Storage's own blob routes are off. `/rails/active_storage/
    # blobs/redirect/:signed_id` takes a signed blob id and nothing else:
    # no session, no owner, and — since `urls_expire_in` is unset by
    # default — no expiry. Whoever holds one has the file for ever,
    # whatever has happened to their access since, which made "take them
    # out of the set and they lose it" untrue of the files.
    #
    # Downloads go through this application's own routes instead, where
    # the record the route names is what authorises the read and every
    # request re-asks. See AttachmentDownload.
    #
    # What is redrawn below (config/routes.rb) is the two things turning
    # these off would otherwise take with them: direct uploads, which
    # every upload in the application depends on, and the Disk service's
    # own endpoints, which are how `blob.url` resolves wherever the
    # service is Disk rather than S3 — the test environment.
    config.active_storage.draw_routes = false

    # Use the project-owned MailDeliveryJob subclass so mail-only retry
    # (Net::OpenTimeout → polynomial backoff) doesn't leak onto every
    # other ApplicationJob descendant. See app/jobs/mail_delivery_job.rb.
    config.action_mailer.delivery_job = 'MailDeliveryJob'

    api_paths = %r{\A/api(/|\z)}

    [
      Rack::MethodOverride,
      ActionDispatch::Cookies,
      ActionDispatch::Session::CookieStore,
      ActionDispatch::Flash
    ].each do |middleware|
      config.middleware.use Middleware::PathScoped, middleware, except: api_paths
    end
  end
end
