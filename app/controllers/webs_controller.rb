class WebsController < ActionController::Base
  # Serve the SPA shell, injecting the runtime configuration that must not be baked
  # into the environment-agnostic build (so a single image can be promoted across
  # environments). The frontend reads these <meta> tags on boot.
  #
  # The shell deliberately lives outside public/ so the static file server never
  # serves it directly, which would bypass this injection. Every document request is
  # routed here instead (see config/routes.rb); the Dockerfile moves the built shell
  # into place.
  def show
    html = Rails.root.join('app/views/webs/show.html').read
    meta = helpers.safe_join([
      helpers.tag.meta(name: 'sentry-dsn',         content: Rails.application.config_for(:app).sentry_dsn),
      helpers.tag.meta(name: 'sentry-environment', content: Rails.env),

      # The sign-in page names where the login button leaves for. The host
      # differs per environment, so it cannot be baked into the build.
      helpers.tag.meta(name: 'identity-provider',  content: Rails.application.config_for(:keycloak).url)
    ])

    render html: html.sub('</head>') { "#{meta}</head>" }.html_safe
  end
end
