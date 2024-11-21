class Database::DRA::Submitter
  def submit(submission)
    submitter_id = submission.validation.user.uid
    user_id      = SubmitterDB::Login.where(submitter_id:).pick(:usr_id)

    DRMDB::Record.transaction isolation: Rails.env.test? ? nil : :serializable do
      serial = (DRMDB::Submission.where(submitter_id:).maximum(:serial) || 0) + 1

      dra_submission = DRMDB::Submission.create!(
        usr_id:       user_id,
        submitter_id:,
        serial:,
        create_date:  Date.current
      )

      dra_submission.status_histories.create! status: :data_validated

      submission_group = dra_submission.create_submission_group!(
        submit_version: 1,
        valid:          true,
        serial_version: 1
      )

      submission_id = "#{submitter_id}-#{serial.to_s.rjust(4, '0')}"
      center_name   = SubmitterDB::Organization.where(submitter_id:).pick(:center_name)
      objs          = submission.validation.objs.where(_id: %w(Submission Experiment Run Analysis))

      acc_entities_assoc = objs.map { |obj|
        DRMDB::AccessionEntity.create!(
          alias:       "#{submission_id}_#{obj._id}_0001",
          center_name:,
          acc_type:    obj._id.downcase
        )
      }.index_by(&:acc_type)

      objs.each do |obj|
        parent_acc_entity = case obj._id
        when "Submission"
          nil
        when "Study", "Sample"
          acc_entities_assoc["DRA"]
        when "Sample"
          acc_entities_assoc["sample"]
        when "Experiment"
          acc_entities_assoc["sample"] || acc_entities_assoc["study"]
        when "Run"
          acc_entities_assoc["DRX"]
        when "Analysis"
          acc_entities_assoc["study"]
        else
          raise "must not happen"
        end

        submission_group.accession_relations.create!(
          accession_entity:        acc_entity,
          parent_accession_entity: parent_acc_entity
        ) do |relation|
          relation.build_meta_entity(
            accession_entity: acc_entity,
            meta_version:     1,
            type:             obj._id.downcase,
            content:          obj.file.download
          )
        end

        ext_entity = DRMDB::ExtEntity.create!(
          acc_type: :submission,
          ref_name: "160053",
          status:   :valid
        )

        submission_group.ext_relations.create!(
          acc_id: acc_entity.acc_id,
          ext_id: ext_entity.ext_id
        ) do |relation|
          relation.build_ext_permit(
            ext_id:       ext_entity.ext_id,
            submitter_id:
          )
        end
      end

      host, user, key_data = ENV.values_at("DRA_SSH_HOST", "DRA_SSH_USER", "DRA_SSH_KEY_DATA")

      Net::SSH.start host, user, key_data: [ key_data ] do |ssh|
        ssh.exec! "sudo /usr/local/sbin/chroot-createdir.sh #{submitter_id} #{submission_id}"
      end
    end
  end
end
