if Rails.env.test?
  Rails.application.routes.default_url_options = {
    protocol: 'http',
    host:     'www.example.com',
    port:     80
  }
else
  url = URI.parse(Rails.application.config_for(:app).app_url!)

  Rails.application.routes.default_url_options = {
    protocol: url.scheme,
    host:     url.host,
    port:     url.port
  }
end
