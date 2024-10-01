module FetchRaiseError
  class Error < StandardError
    def initialize(res)
      super "#{res.status} #{res.status_text}: #{res.body}"
    end
  end

  class ClientError < Error; end
  class ServerError < Error; end

  refine Fetch::Response do
    def ensure_ok
      case status
      when 400..499
        raise ClientError, self
      when 500..599
        raise ServerError, self
      end

      self
    end
  end
end