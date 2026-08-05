class CloakmanClient
  # DDBJ Account's `account_type_number`, as Cloakman declares it.
  #
  # The two ways we receive it disagree on shape: the OIDC id token
  # carries the integer, the REST profile carries the name. Mapping both
  # to the name here is what stops a bare `== 3` from appearing at each
  # call site.
  ACCOUNT_TYPES = {
    1 => 'general',
    2 => 'nbdc',
    3 => 'ddbj',
    4 => 'administrator',
    5 => 'system_reference'
  }.freeze

  # Acronyms, so `humanize` is not good enough.
  ACCOUNT_TYPE_LABELS = {
    'general'          => 'General',
    'nbdc'             => 'NBDC',
    'ddbj'             => 'DDBJ',
    'administrator'    => 'Administrator',
    'system_reference' => 'System reference'
  }.freeze

  # What makes somebody a curator here. Exactly `ddbj` — `administrator`
  # is a systems role in DDBJ Account, on a different axis entirely from
  # who curates submissions, so it is not staff for our purposes however
  # much its name suggests otherwise.
  STAFF_ACCOUNT_TYPE = 'ddbj'

  def self.account_type_name(raw)
    ACCOUNT_TYPES.fetch(raw) { raw.presence&.to_s }
  end

  def initialize(config: Rails.application.config_for(:cloakman))
    @config = config
  end

  def search(query)
    connection.get('api/users', {query:}).body
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
