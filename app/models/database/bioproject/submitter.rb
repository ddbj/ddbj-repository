class Database::BioProject::Submitter
  class Error < StandardError; end
  class SubmissionIDOverflow < Error; end

  PROJECT_DATA_TYPES = {
    'Genome Sequencing'                => 'genome_sequencing',
    'Clone Ends'                       => 'clone_ends',
    'Epigenomics'                      => 'epigenomics',
    'Exome'                            => 'exome',
    'Map'                              => 'map',
    'Metagenome'                       => 'metagenome',
    'Phenotype and Genotype'           => 'phenotype_and_genotype',
    'Proteome'                         => 'proteome',
    'Random Survey'                    => 'random_survey',
    'Targeted Locus (Loci)'            => 'targeted_locus_loci',
    'Transcriptome or Gene Expression' => 'transcriptome_or_gene_expression',
    'Variation'                        => 'variation',
    'Other'                            => 'other'
  }

  def submit(submission)
    user         = submission.validation.user
    submitter_id = user.uid

    BioProject::Record.transaction isolation: Rails.env.test? ? nil : :serializable do |tx|
      begin
        submission_id = next_submission_id
      rescue SubmissionIDOverflow => e
        tx.after_rollback do
          BioProject::ActionHistory.create!(
            action:       "[repository:CreateNewSubmission] #{e.message}",
            action_date:  Time.current,
            result:       false,
            action_level: 'fatal',
            submitter_id:
          )
        end

        raise
      end

      tx.after_rollback do
        BioProject::ActionHistory.create!(
          action:       '[repository:CreateNewSubmission] rollback transaction',
          action_date:  Time.current,
          result:       false,
          action_level: 'error',
          submitter_id:
        )
      end

      bp_submission = BioProject::Submission.create!(
        submission_id:,
        submitter_id:,
        status_id:         :data_submitted,
        form_status_flags: '000000'
      )

      content   = submission.validation.objs.find_by!(_id: 'BioProject').file.download
      doc       = Nokogiri::XML.parse(content)
      is_public = submission.visibility_public?
      hold      = doc.at('/PackageSet/Package/Submission/Submission/Description/Hold')

      if is_public && hold
        raise Error, 'Visibility is public, but Hold exist in XML.'
      elsif !is_public && !hold
        raise Error, 'Visibility is private, but Hold does not exist in XML.'
      end

      set_accession_and_archive doc, submission_id
      set_release_date doc if is_public
      set_tax_id doc

      bp_submission.create_project!(
        project_type:  'primary',
        status_id:     is_public ? :public : :private,
        release_date:  is_public ? Time.current : nil,
        dist_date:     is_public ? Time.current : nil,
        modified_date: Time.current
      )

      bp_submission.submission_data.insert_all submission_data_attrs(submission, doc)

      version = (BioProject::XML.where(submission_id:).order(version: :desc).pick(:version) || 0) + 1

      bp_submission.xmls.create!(
        content:         doc.to_s,
        version:,
        registered_date: Time.current
      )

      bp_submission.action_histories.create!(
        action:       '[repository:CreateNewSubmission] Create new submission',
        action_date:  Time.current,
        result:       true,
        action_level: 'info',
        submitter_id:
      )

      tx.after_commit do
        DRMDB::ExtEntity.create!(
          acc_type: :study,
          ref_name: submission_id,
          status:   :valid
        ) do |entity|
          entity.ext_permits.build(
            submitter_id:
          )
        end
      end
    end
  end

  private

  def next_submission_id
    submission_id = BioProject::Submission.order(submission_id: :desc).pick(:submission_id) || 'PSUB000000'
    num           = submission_id.delete_prefix('PSUB').to_i

    raise SubmissionIDOverflow, 'Number of submission surpass the upper limit' if num >= 999_999

    "PSUB#{num.succ.to_s.rjust(6, '0')}"
  end

  def set_accession_and_archive(doc, project_id)
    archive_id = doc.at('/PackageSet/Package/Project/Project/ProjectID/ArchiveID')

    archive_id[:accession] = project_id
    archive_id[:archive]   = 'DDBJ'
  end

  def set_release_date(doc)
    doc.at('/PackageSet/Package/Submission/Submission/Description/Hold')&.remove

    if release_date = doc.at('/PackageSet/Package/Project/Project/ProjectDescr/ProjectReleaseDate')
      if release_date.text.empty?
        release_date.content = Time.current.iso8601
      end
    else
      # TODO: Error handling
    end
  end

  def set_tax_id(doc)
    return if doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/@taxID')

    organism_name = doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/OrganismName').text
    names         = DRASearch::TaxName.where(search_name: organism_name, name_class: 'scientific name').order(:tax_id)

    tax_id = case names.size
    when 0
      nil
    when 1
      names.first.tax_id
    else
      ids = names.map { "[#{_1.tax_id}] #{_1.uniq_name}" }.join(', ')

      raise Error, "Organism name is ambiguous, please set one of the following taxonomy IDs: #{ids}"
    end

    raise Error, 'No entry found for the given organism name.' unless tax_id

    doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism')[:taxID] = tax_id
  end

  def submission_data_attrs(submission, doc)
    [
      *doc.xpath('/PackageSet/Package/Submission/Submission/Description/Organization/Contact').flat_map.with_index(1) {|contact, i|
        first_name = contact.at('Name/First')
        last_name  = contact.at('Name/Last')
        email      = contact[:email]

        [
          ['submitter', 'first_name', first_name&.text, i],
          ['submitter', 'last_name',  last_name&.text,  i],
          ['submitter', 'email',      email,            i]
        ]
      },

      doc.at('/PackageSet/Package/Submission/Submission/Description/Organization/Name').then {
        ['submitter', 'organization_name', _1&.text, -1]
      },

      doc.at('/PackageSet/Package/Submission/Submission/Description/Organization/@url').then {
        ['submitter', 'organization_url', _1&.text, -1]
      },

      ['submitter', 'data_release', submission.visibility_public? ? 'nonhup' : 'hup', -1],

      doc.at('/PackageSet/Package/Project/Project/ProjectDescr/Title').then {
        ['general_info', 'project_title', _1&.text, -1]
      },

      doc.at('/PackageSet/Package/Project/Project/ProjectDescr/Description').then {
        ['general_info', 'public_description', _1&.text, -1]
      },

      *doc.xpath('/PackageSet/Package/Project/Project/ProjectDescr/ExternalLink').flat_map.with_index(1) {|link, i|
        url = link.at('URL')

        [
          ['general_info', 'link_description', link[:label], i],
          ['general_info', 'link_url',         url&.text,    i]
        ]
      },

      *doc.xpath('/PackageSet/Package/Project/Project/ProjectDescr/Grant').flat_map.with_index(1) {|grant, i|
        agency = grant.at('Agency')
        abbr   = grant.at('Agency/@abbr')
        title  = grant.at('Title')

        [
          ['general_info', 'agency',              agency&.text,    i],
          ['general_info', 'agency_abbreviation', abbr&.text,      i],
          ['general_info', 'grant_id',            grant[:GrantId], i],
          ['general_info', 'grant_title',         title&.text,     i]
        ]
      },

      *doc.xpath('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/ProjectDataTypeSet/DataType').flat_map.with_index(1) {|data_type, i|
        if value = PROJECT_DATA_TYPES[data_type.text]
          [
            ['project_type', 'project_data_type', value, i]
          ]
        else
          [
            ['project_type', 'project_data_type',             'other',        i],
            ['project_type', 'project_data_type_description', data_type.text, i]
          ]
        end
      },

      *doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target').then {
        [
          ['project_type', 'sample_scope', _1&.[](:sample_scope), -1],
          ['project_type', 'material',     _1&.[](:material),     -1],
          ['project_type', 'capture',      _1&.[](:capture),      -1]
        ]
      },

      *doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Method').then {
        method_type = _1&.[](:method_type)
        description = method_type == 'eOther' ? _1&.text : nil

        [
          ['project_type', 'methodology',             method_type, -1],
          ['project_type', 'methodology_description', description, -1]
        ]
      },

      *doc.xpath('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Objectives').map.with_index(1) {|objectives, i|
        data = objectives.at('Data')

        ['project_type', 'objective', data&.[](:data_type), i]
      },

      doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/OrganismName').then {
        ['target', 'organism_name', _1&.text, -1]
      },

      doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/@taxID').then {
        ['target', 'taxonomy_id', _1.text == '0' ? nil : _1.text, -1]
      },

      doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/Strain').then {
        ['target', 'strain_breed_cultivar', _1&.text, -1]
      },

      doc.at('/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/Label').then {
        ['target', 'isolate_name_or_label', _1&.text, -1]
      },

      *doc.xpath('/PackageSet/Package/Project/Project/ProjectDescr/Publication').map.with_index(1) {|publication, i|
        case dbtype = publication.at('Reference/DbType')&.text
        when 'ePubmed'
          ['publication', 'pubmed_id', publication[:id], i]
        when 'eDOI'
          ['publication', 'doi', publication[:id], i]
        else
          raise Error, "Unsupported publication type: #{dbtype.inspect}"
        end
      }
    ].compact.map {|form_name, data_name, data_value, t_order|
      {
        form_name:,
        data_name:,
        data_value:,
        t_order:
      }
    }
  end
end
