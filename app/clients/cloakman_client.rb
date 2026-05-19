class CloakmanClient
  def initialize(config: Rails.application.config_for(:cloakman))
    @config = config
  end

  def users(query: nil, uids: nil)
    return [] if uids&.empty?

    res = connection.get('api/users', {query:, uids:}.compact)

    res.body
  end

  private

  def connection
    @connection ||= Faraday.new(url: @config.url!) {|f|
      f.request  :authorization, 'Bearer', @config.api_token!
      f.response :json
      f.response :raise_error
    }
  end
end
