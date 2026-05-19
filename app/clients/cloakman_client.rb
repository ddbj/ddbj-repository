class CloakmanClient
  def initialize(config: Rails.application.config_for(:cloakman))
    @config = config
  end

  def search(query)
    connection.get('api/users', {query:}.compact).body
  end

  def lookup(uids)
    return [] if uids.empty?

    connection.get('api/users/lookup', {uids:}).body
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
