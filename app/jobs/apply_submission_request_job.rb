class ApplySubmissionRequestJob < ApplicationJob
  # 分類できた失敗だけがコードを持ち、残りは catch-all になる。増やすときはここに 1 行
  # 足して README の表に書く。クライアントは知らないコードを catch-all と同じに扱えば
  # よいので、追加は常に additive。
  #
  # error_message の方は人間向けで、文言は予告なく変わる。**機械的な判断はコードで
  # 行うこと。**
  ERROR_CODES = {
    Sequence::Exhausted                      => 'TRD_R0012',
    SubmissionApply::St26::MalformedLocusDate => 'TRD_R0014'
  }.freeze

  UNEXPECTED_ERROR_CODE = 'TRD_R9999'

  def perform(request)
    # 前回の失敗の痕跡を残さない。コードは機械的な判断に使われるので、古い値が
    # 残っていると「今まさに失敗している」と読まれる。
    request.update!(
      status:        :applying,
      error_code:    nil,
      error_message: nil
    )

    SubmissionApply.for(request.db).call request
  rescue Exception => e # rubocop:disable Lint/RescueException
    # StandardError 以外（SystemStackError 等）でも必ず終端状態に落とす。
    # ここで取り逃すと request が applying のまま取り残され、クライアントが
    # status を永久にポーリングし続ける。シグナル等は記録だけして上位へ流す。
    Rails.error.report e

    request.update!(
      status:        :application_failed,
      error_code:    error_code_for(e),
      error_message: e.message
    )

    raise unless e.is_a?(StandardError)
  else
    request.applied!
  end

  private

  def error_code_for(error)
    _, code = ERROR_CODES.find {|klass, _| error.is_a?(klass) }

    code || UNEXPECTED_ERROR_CODE
  end
end
