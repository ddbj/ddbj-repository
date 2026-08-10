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

      transaction {
        lock.find_by!(scope:).allocate!(count)
      }
    end
  end

  # scope に割り当てられた prefix の一覧。先頭から順に使い切っていく。
  def prefixes = self.class.config.fetch(scope.to_sym)

  # 次に払い出される番号。使い切っていれば nil。
  #
  # allocate! は使い切った prefix を送る仕事を次の呼び出しに残すので、`next` が
  # 今の prefix の最大値を超えたまま休んでいることがある。表示する側はそれを
  # 解決してからでないと、桁の合わない番号（QP1000000）を名乗ってしまう。
  def peek
    i, value = position

    i && format_number(prefixes[i], value)
  end

  def total = prefixes.sum { max_value(it) }

  # 送りを解決する必要はない。next が最大値を超えていても、それは今の prefix を
  # 使い切ったという意味で、消費数としては正しい。
  def used = prefixes.take(current_index).sum { max_value(it) } + (self.next - 1)

  def remaining = total - used

  # count 個を払い出して番号の配列を返す。足りなければ 1 個も払い出さない
  # （呼び出し側がトランザクションを張っているので、raise でここの update! も巻き戻る）。
  def allocate!(count)
    out = []

    while count > 0
      i       = current_index
      entry   = prefixes[i]
      max_val = max_value(entry)
      start   = self.next
      avail   = max_val - start + 1

      # 使い切った prefix から次へ送るのはここだけ。まだ採番が残っているのに次が無い
      # ときだけ Exhausted になる。
      #
      # **この例外はクライアントが分岐に使う。** ApplySubmissionRequestJob::ERROR_CODES が
      # TRD_R0012 に対応づけ、submission_requests.error_code に載せている（README の表）。
      # クラスを変えたり別の例外に差し替えたりするときは、あちらも一緒に直すこと。
      # 文言の方は人間向けなので自由に変えてよい。
      if avail <= 0
        raise Exhausted, "#{scope}: no numbers left after #{prefix} (wanted #{count} more)" if i + 1 >= prefixes.size

        update!(
          prefix: prefixes[i + 1][:prefix],
          next:   1
        )

        next
      end

      take = [count, avail].min
      stop = start + take - 1

      out.concat (start..stop).map { format_number(entry, it) }
      count -= take

      # 使い切った場合は next が max_val + 1 になり、次の周回（あるいは次の呼び出し）が
      # 上で送る。ここで送ろうとすると、最後の prefix の最終番号でぴったり終わった採番が
      # 「次の prefix が無い」という理由で Exhausted になり、全件成功しているのに
      # ロールバックされる。その番号は永久に払い出せなくなる。
      update! next: stop + 1
    end

    out
  end

  private

  def current_index
    prefixes.index { it[:prefix] == prefix } or raise "Prefix #{prefix} not found in scope #{scope}"
  end

  # 送りを解決した [prefix の位置, 番号]。使い切っていれば nil。
  def position
    i = current_index

    return [i, self.next] if self.next <= max_value(prefixes[i])

    [i + 1, 1] if i + 1 < prefixes.size
  end

  def max_value(entry) = (10 ** entry[:digits]) - 1

  def format_number(entry, value)
    entry.fetch(:pad, true) ? "#{entry[:prefix]}#{value.to_s.rjust(entry[:digits], '0')}" : "#{entry[:prefix]}#{value}"
  end
end
