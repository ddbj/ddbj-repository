# frozen_string_literal: true

module DDBJRecord
  class Writer
    def initialize(io)
      @writer = Oj::StreamWriter.new(io, indent: 2)
    end

    def write(record)
      write_value record

      @writer.flush
    end

    private

    def write_value(value, key = nil)
      case value
      when Data
        write_data value, key
      when Hash
        write_hash value, key
      when Array
        write_array value, key
      else
        @writer.push_value value, key
      end
    end

    def write_data(data, key = nil)
      @writer.push_object key

      data.members.each do |member|
        value = data.public_send(member)

        next if value.nil?

        if data.is_a?(Provenance) && member == :extras
          value.each {|k, v| write_value(v, k.to_s) }
        else
          write_value value, member.name
        end
      end

      @writer.pop
    end

    def write_hash(hash, key = nil)
      @writer.push_object key

      hash.each do |k, v|
        write_value v, k.to_s
      end

      @writer.pop
    end

    def write_array(array, key = nil)
      @writer.push_array key

      array.each do |i|
        write_value i
      end

      @writer.pop
    end
  end
end
