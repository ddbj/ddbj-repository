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
      user = submission.validation.user

      Dway.bioproject.transaction isolation: :serializable do
        submission_id = next_submission_id
        submitter_id  = user.uid

        Dway.bioproject[:submission].insert(
          submission_id:     ,
          submitter_id:      ,
          status_id:         BP_SUBMISSION_STATUS_ID_DATA_SUBMITTED,
          form_status_flags: ''
        )

        is_public = submission.visibility_public?

        project_id = Dway.bioproject[:project].insert(
          submission_id: ,
          project_type:  'primary',
          status_id:     is_public ? BP_PROJECT_STATUS_ID_PUBLIC : BP_PROJECT_STATUS_ID_PRIVATE,
          release_date:  is_public ? Sequel.function(:now)       : nil,
          dist_date:     is_public ? Sequel.function(:now)       : nil,
          modified_date: Sequel.function(:now)
        )

        content = submission.validation.objs.find_by!(_id: 'BioProject').file.download
        doc     = Nokogiri::XML.parse(content)
        version = (Dway.bioproject[:xml].where(submission_id:).max(:version) || 0) + 1

        modify_xml doc, project_id, is_public

        Dway.bioproject[:xml].insert(
          submission_id:   ,
          content:         doc.to_s,
          version:         ,
          registered_date: Sequel.function(:now)
        )

        Dway.drmdb.transaction do
          ext_id = Dway.drmdb[:ext_entity].insert(
            acc_type: SCHEMA_TYPE_STUDY,
            ref_name: submission_id,
            status:   EXT_STATUS_VALID
          )

          Dway.drmdb[:ext_permit].insert(
            ext_id:       ext_id,
            submitter_id:
          )
        end

        {
          first_name:        user.first_name,
          last_name:         user.last_name,
          email:             user.email,
          organization_name: [user.department, user.organization].compact_blank.join(', '),
          organization_url:  user.organization_url
        }.each.with_index 1 do |(key, value), i|
          Dway.bioproject[:submission_data].insert(
            submission_id: ,
            data_name:     key.to_s,
            data_value:    value.to_s,
            form_name:     'submitter',
            t_order:       i
          )
        end
      end
    end

    private

    def next_submission_id
      submission_id = Dway.bioproject[:submission].reverse(:submission_id).get(:submission_id) || 'PSUB000000'
      num           = submission_id.delete_prefix('PSUB').to_i

      "PSUB#{num.succ.to_s.rjust(6, '0')}"
    end

    def modify_xml(doc, project_id, is_public)
      archive_id = doc.at('/PackageSet/Package/Project/Project/ProjectID/ArchiveID')

      archive_id[:accession] = project_id
      archive_id[:archive]   = 'DDBJ'

      if is_public
        doc.at('/PackageSet/Package/Submission/Submission/Description/Hold')&.remove

        if release_date = doc.at('/PackageSet/Package/Project/Project/ProjectDescr/ProjectReleaseDate')
          if release_date.text.empty?
            release_date.content = Time.current.iso8601
          end
        else
          # TODO: Error handling
        end
      end

      doc
    end
  end
end
