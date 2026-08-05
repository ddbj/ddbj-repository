Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins '*'

    resource '/api/*', **{
      headers: :any,
      # A header the browser cannot read may as well not be sent — the
      # phase tabs read their counts from these two.
      expose:  %w[Link Current-Page Page-Items Total-Pages Total-Count Unfinished-Count Finished-Count],
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
