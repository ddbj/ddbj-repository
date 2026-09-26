namespace :ddbj_record do
  # Rewrites every stored record (BioProject and BioSample are the ones the
  # change reaches) into the shape the spec's v3 took at
  # ddbj/ddbj-record-specifications#11 (DDBJRecord::ReshapeV3), as one root
  # replace per chain under ddbj-canon/v3 — the heal
  # Submission#append_update! performs for a chain written under an older
  # version. Edits made in the repository stay: the record rewritten is the
  # materialised one, not a fresh conversion from D-way.
  #
  # Idempotent: a chain already under the current version and in the new
  # shape gets no update. Nothing depends on when it runs — a chain it has
  # not reached yet is read in the current shape, and healed by the first
  # write to it — but running it once after deploying heals them all.
  #
  #   bin/rails ddbj_record:reshape_v3
  desc 'Rewrite stored records into the current v3 shape and heal their chains'
  task reshape_v3: :environment do
    counts = Hash.new(0)

    Submission.where.associated(:updates).distinct.find_each do |submission|
      # The chain as it stores it — replayed, not read through the cache,
      # which the rewrite is about to invalidate anyway.
      record = submission.materialise_at
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
