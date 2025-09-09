class Sequence < ApplicationRecord
  class Exhausted < StandardError; end

  class << self
    def config = Rails.application.config_for(:sequence)

    def ensure_records!
      insert_all config.map {|scope, list|
        {
          scope:,
          prefix: list.first[:prefix],
          digits: list.first[:digits]
        }
      }, unique_by: :scope
    end

    def allocate!(scope, count:)
      list = config.fetch(scope)

      transaction do
        seq = lock.find_by!(scope:)

        unless i = list.index { it[:prefix] == seq.prefix }
          raise "Prefix #{seq.prefix} not found in scope #{scope}"
        end

        digits  = list[i][:digits]
        max_val = (10 ** digits) - 1
        start   = seq.next
        stop    = start + count - 1

        if stop > max_val
          raise Exhausted if i + 1 >= list.size

          head       = format_range(seq.prefix, start, max_val, digits)
          next_entry = list[i + 1]

          seq.update!(
            prefix: next_entry[:prefix],
            next:   1,
            digits: next_entry[:digits]
          )

          tail = allocate!(scope, count: count - head.size)

          head + tail
        else
          seq.update! next: stop + 1

          format_range(seq.prefix, start, stop, digits)
        end
      end
    end

    private

    def format_range(prefix, from, to, digits)
      (from..to).map { "#{prefix}#{it.to_s.rjust(digits, '0')}" }
    end
  end
end
