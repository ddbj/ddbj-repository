module WebRedirect
  extend ActiveSupport::Concern

  private

  def redirect_to_web(path = '/', **params)
    url = URI.join(Rails.application.config_for(:app).web_url!, path)
    url.query = URI.encode_www_form(params) if params.any?

    redirect_to url.to_s, allow_other_host: true
  end
end
