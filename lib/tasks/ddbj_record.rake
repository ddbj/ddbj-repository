namespace :ddbj_record do
  # Rewrites every stored BioProject / BioSample record into the shape the
  # spec's v3 took at ddbj/ddbj-record-specifications#11 (DDBJRecord::ReshapeV3),
  # as one root replace per chain under ddbj-canon/v3 — the heal
  # Submission#append_update! performs for a chain written under an older
  # version. Edits made in the repository stay: the record rewritten is the
  # materialised one, not a fresh conversion from D-way.
  #
  # Idempotent: a chain already under the current version and in the new
  # shape gets no update. Run once after deploying, before the next import.
  #
  #   bin/rails ddbj_record:reshape_v3
  desc 'Rewrite stored BioProject / BioSample records into the current v3 shape'
  task reshape_v3: :environment do
    counts = Hash.new(0)

    Submission.where(db: %w[bioproject biosample]).where.associated(:updates).distinct.find_each do |submission|
      record = submission.materialised_record
      next counts[:empty] += 1 if record.blank?

      reshaped = DDBJRecord::ReshapeV3.call(record)

      if reshaped == record && !submission.legacy_chain?
        counts[:unchanged] += 1
      else
        submission.append_update!(reshaped, actor: 'ddbj_record:reshape_v3', source: :batch)
        counts[:rewritten] += 1
      end
    rescue Submission::MaterialisationFailed => e
      counts[:failed] += 1
      warn "#{submission.db} submission #{submission.id}: #{e.message}"
    end

    puts counts.map {|outcome, n| "#{outcome}: #{n}" }.join(', ')
    abort 'Some records could not be read; see above.' if counts[:failed].positive?
  end
end
