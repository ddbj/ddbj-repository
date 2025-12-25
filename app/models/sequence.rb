class Sequence < ApplicationRecord
  class Exhausted < StandardError; end

  class << self
    def config = Rails.application.config_for(:sequence)

    def ensure_records!
      insert_all config.map {|scope, list|
        {
          scope:,
          prefix: list.first[:prefix]
        }
      }, unique_by: :scope
    end

    def allocate!(scope, count)
      ensure_records!

      list = config.fetch(scope)

      transaction do
        seq = lock.find_by!(scope:)
        out = []

        while count > 0
          unless i = list.index { it[:prefix] == seq.prefix }
            raise "Prefix #{seq.prefix} not found in scope #{scope}"
          end

          digits  = list[i][:digits]
          max_val = (10 ** digits) - 1
          start   = seq.next
          avail   = max_val - start + 1

          if avail <= 0
            raise Exhausted if i + 1 >= list.size

            seq.update!(
              prefix: list[i + 1][:prefix],
              next:   1
            )

            next
          end

          take = [count, avail].min
          stop = start + take - 1

          out.concat format_range(seq.prefix, start, stop, digits)
          count -= take

          if stop == max_val
            raise Exhausted if i + 1 >= list.size

            seq.update!(
              prefix: list[i + 1][:prefix],
              next:   1
            )
          else
            seq.update! next: stop + 1
          end
        end

        out
      end
    end

    private

    def format_range(prefix, from, to, digits)
      (from..to).map { "#{prefix}#{it.to_s.rjust(digits, '0')}" }
    end
  end
end
