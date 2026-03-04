module DDBJRecord
  module DataExtensions
    def as_json(*)
      members.each_with_object({}) {|key, hash|
        value = public_send(key)

        next if value.nil?

        hash[key.name] = serialize(value)
      }
    end

    private

    def serialize(value)
      case value
      when DataExtensions
        value.as_json
      when Hash
        value.to_h {|k, v| [k.to_s, serialize(v)] }
      when Array
        value.map { serialize(it) }
      else
        value
      end
    end
  end
end
