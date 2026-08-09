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
          pad     = list[i].fetch(:pad, true)
          max_val = (10 ** digits) - 1
          start   = seq.next
          avail   = max_val - start + 1

          # 使い切った prefix から次へ送るのはここだけ。まだ採番が残っているのに次が無い
          # ときだけ Exhausted になる。
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

          out.concat format_range(seq.prefix, start, stop, digits, pad)
          count -= take

          # 使い切った場合は next が max_val + 1 になり、次の周回（あるいは次の呼び出し）が
          # 上で送る。ここで送ろうとすると、最後の prefix の最終番号でぴったり終わった採番が
          # 「次の prefix が無い」という理由で Exhausted になり、全件成功しているのに
          # ロールバックされる。その番号は永久に払い出せなくなる。
          seq.update! next: stop + 1
        end

        out
      end
    end

    private

    def format_range(prefix, from, to, digits, pad)
      (from..to).map { "#{prefix}#{pad ? it.to_s.rjust(digits, '0') : it.to_s}" }
    end
  end
end
