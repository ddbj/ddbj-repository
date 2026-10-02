class ApplySubmissionRequestJob < ApplicationJob
  # 分類できた失敗だけがコードを持ち、残りは catch-all になる。増やすときはここに 1 行
  # 足して README の表に書く。クライアントは知らないコードを catch-all と同じに扱えば
  # よいので、追加は常に additive。
  #
  # error_message の方は人間向けで、文言は予告なく変わる。**機械的な判断はコードで
  # 行うこと。**
  ERROR_CODES = {
    Sequence::Exhausted                       => 'TRD_R0012',
    SubmissionApply::St26::MalformedLocusDate => 'TRD_R0014',
    SubmissionApply::DRARecord::FilesGone     => 'TRD_R0025'
  }.freeze

  UNEXPECTED_ERROR_CODE = 'TRD_R9999'

  # Another run of this request has it (AdvisoryLock): wait for it to end,
  # since it may yet die without finishing.
  retry_on AdvisoryLock::Held, wait: 1.minute, attempts: :unlimited

  # One run per request (AdvisoryLock). A job is run again from the start
  # when it was stopped part way (RecoverKilledJobsJob), and each database's
  # apply carries on from what it committed — but the run it replaces may
  # be alive yet, and two at once would apply the record twice.
  #
  # Read again under the lock: the run it waited for may have applied it
  # since. And only while the request waits to be applied — a late run of
  # an applied one would otherwise flip it back through applying.
  def perform(request)
    AdvisoryLock.exclusively "apply_submission_request:#{request.id}" do
      request.reload

      apply request if request.waiting_application? || request.applying?
    end
  end

  private

  def apply(request)
    # 前回の失敗の痕跡を残さない。コードは機械的な判断に使われるので、古い値が
    # 残っていると「今まさに失敗している」と読まれる。
    settle request, status: 'applying', error_code: nil, error_message: nil

    SubmissionApply.for(request.db).call request
  rescue Exception => e # rubocop:disable Lint/RescueException
    # StandardError 以外（SystemStackError 等）でも必ず終端状態に落とす。
    # ここで取り逃すと request が applying のまま取り残され、クライアントが
    # status を永久にポーリングし続ける。シグナル等は記録だけして上位へ流す。
    Rails.error.report e

    fail! request, e

    raise unless e.is_a?(StandardError)
  else
    settle request, status: 'applied'
  end

  def fail!(request, error)
    # What the apply left on the request goes with its rolled-back
    # transaction — above all the submission it linked, which no longer
    # exists. (ST.26's numbers, submission and entries are a commit of their
    # own, so those stay, and sending the request again carries on from
    # them.)
    request.reload

    _, code = ERROR_CODES.find {|klass, _| error.is_a?(klass) }

    settle request, status: 'application_failed', error_code: code || UNEXPECTED_ERROR_CODE, error_message: error.message
  end

  # Straight to the columns, as DDBJValidatorCheck.conclude writes its
  # answer: a request whose own validations no longer pass (its assignee
  # stopped being a curator) must still be told how it went, or it would
  # stay applying.
  def settle(request, **columns)
    request.update_columns(**columns, updated_at: Time.current)
  end
end
