module Database::BioProject
  class Validator
    include DDBJValidator
  end

  class Submitter
    BP_PROJECT_STATUS_ID_PRIVATE           = 5400
    BP_PROJECT_STATUS_ID_PUBLIC            = 5500
    BP_SUBMISSION_STATUS_ID_DATA_SUBMITTED = 700
    EXT_STATUS_INPUTTING                   = 0
    EXT_STATUS_VALID                       = 100
    EXT_STATUS_INVALID                     = 1000
    SCHEMA_TYPE_SUBMISSION                 = 1
    SCHEMA_TYPE_STUDY                      = 2
    SCHEMA_TYPE_SAMPLE                     = 3
    SCHEMA_TYPE_EXPERIMENT                 = 4
    SCHEMA_TYPE_RUN                        = 5
    SCHEMA_TYPE_ANALYSIS                   = 6

    def submit(submission)
      Dway.bioproject.transaction isolation: :serializable do
        submitter_id         = submission.validation.user.uid
        latest_submission_id = Dway.bioproject[:submission].reverse(:submission_id).get(:submission_id)
        submission_id        = next_submission_id(latest_submission_id || 'PSUB000000')
        version              = (Dway.bioproject[:xml].where(submission_id:).max(:version) || 0) + 1

        contact      = Dway.submitterdb[:contact].where(submitter_id:, is_pi: true).first
        organization = Dway.submitterdb[:organization].where(submitter_id:).first

        {
          first_name:        contact[:first_name],
          last_name:         contact[:last_name],
          email:             contact[:email],
          organization_name: organization.fetch_values(:unit, :affiliation, :department, :organization).compact_blank.join(', '),
          organization_url:  organization[:url],
        }.each.with_index 1 do |(key, value), i|
          Dway.bioproject[:submission_data].insert(
            submission_id: ,
            data_name:     key.to_s,
            data_value:    value.to_s,
            form_name:     'submitter',
            t_order:       i
          )
        end

        Dway.drmdb.transaction do
          ext_id = Dway.drmdb[:ext_entity].insert(
            acc_type: SCHEMA_TYPE_STUDY,
            ref_name: submission_id,
            status:   EXT_STATUS_INPUTTING
          )

          Dway.drmdb[:ext_permit].insert(
            ext_id:       ext_id,
            submitter_id:
          )
        end

        Dway.bioproject[:submission].insert(
          submission_id:     ,
          submitter_id:      ,
          status_id:         BP_SUBMISSION_STATUS_ID_DATA_SUBMITTED,
          form_status_flags: ''
        )

        Dway.drmdb[:ext_entity].where(ref_name: submission_id).update(
          status: EXT_STATUS_VALID
        )

        release_immidiately = false

        project_id = Dway.bioproject[:project].insert(
          submission_id:     ,
          project_type:      'primary',
          status_id:         release_immidiately ? BP_PROJECT_STATUS_ID_PUBLIC : BP_PROJECT_STATUS_ID_PRIVATE,
          release_date:      release_immidiately ? Sequel.lit('NOW()') : nil,
          dist_date:         release_immidiately ? Sequel.lit('NOW()') : nil,
          modified_date:     Sequel.lit('NOW()')
        )

        content    = submission.validation.objs.find_by!(_id: 'BioProject').file.download
        doc        = Nokogiri::XML.parse(content)
        archive_id = doc.at('/PackageSet/Package/Project/Project/ProjectID/ArchiveID')

        archive_id[:accession] = project_id
        archive_id[:archive]   = 'DDBJ'

        if release_immidiately
          doc.at('/PackageSet/Package/Submission/Submission/Description/Hold')&.remove

          if release_date = doc.at('/PackageSet/Package/Project/Project/ProjectDescr/ProjectReleaseDate')
            if release_date.text.empty?
              release_date.content = Time.current.iso8601
            end
          else
            # TODO: Error handling
          end
        end

        Dway.bioproject[:xml].insert(
          submission_id:   ,
          content:         doc.to_s,
          version:         ,
          registered_date: Sequel.lit('NOW()')
        )
      end
    end

    private

    def next_submission_id(submission_id)
      num = submission_id.delete_prefix('PSUB').to_i

      "PSUB#{num.succ.to_s.rjust(6, '0')}"
    end
  end
end
