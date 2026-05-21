Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'

    resource '/api/*', **{
      headers: :any,
      expose:  %w[Link Current-Page Page-Items Total-Pages Total-Count],
      methods: %i[get post put patch delete options head]
    }

    resource '/rails/active_storage/direct_uploads', **{
      headers: :any,
      methods: %i[post]
    }
  end

  allow do
    origins Rails.application.config_for(:app).web_url!

    resource '/session', **{
      headers:     :any,
      methods:     %i[delete options],
      credentials: true
    }
  end
end
