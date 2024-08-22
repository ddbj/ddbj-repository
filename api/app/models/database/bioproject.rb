module Database::BioProject
  class Param
    def self.build(params)
      BioProjectSubmissionParam.new(params.require(:param).permit(:umbrella))
    end
  end

  class Validator
    include DDBJValidator
  end

  class Submitter
    class VisibilityMismatch < StandardError; end 

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

    PROJECT_DATA_TYPES = {
      "Genome Sequencing"                => "genome_sequencing",
      "Clone Ends"                       => "clone_ends",
      "Epigenomics"                      => "epigenomics",
      "Exome"                            => "exome",
      "Map"                              => "map",
      "Metagenome"                       => "metagenome",
      "Phenotype and Genotype"           => "phenotype_and_genotype",
      "Proteome"                         => "proteome",
      "Random Survey"                    => "random_survey",
      "Targeted Locus (Loci)"            => "targeted_locus_loci",
      "Transcriptome or Gene Expression" => "transcriptome_or_gene_expression",
      "Variation"                        => "variation",
      "Other"                            => "other"
    }

    def submit(submission)
      user = submission.validation.user

      Dway.bioproject.transaction isolation: :serializable do
        submission_id = next_submission_id
        submitter_id  = user.uid

        Dway.bioproject[:submission].insert(
          submission_id:,
          submitter_id:,
          status_id:         BP_SUBMISSION_STATUS_ID_DATA_SUBMITTED,
          form_status_flags: ""
        )

        is_public = submission.visibility_public?
        content   = submission.validation.objs.find_by!(_id: "BioProject").file.download
        doc       = Nokogiri::XML.parse(content)
        hold      = !!doc.at("/PackageSet/Package/Submission/Submission/Description/Hold")

        raise VisibilityMismatch if is_public == hold

        project_id = Dway.bioproject[:project].insert(
          submission_id:,
          project_type:  "primary",
          status_id:     is_public ? BP_PROJECT_STATUS_ID_PUBLIC : BP_PROJECT_STATUS_ID_PRIVATE,
          release_date:  is_public ? Sequel.function(:now)       : nil,
          dist_date:     is_public ? Sequel.function(:now)       : nil,
          modified_date: Sequel.function(:now)
        )

        version = (Dway.bioproject[:xml].where(submission_id:).max(:version) || 0) + 1

        modify_xml doc, project_id, is_public

        Dway.bioproject[:xml].insert(
          submission_id:,
          content:         doc.to_s,
          version:,
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

        Dway.bioproject[:submission_data].multi_insert submission_data_attrs(submission, submission_id, doc)
      end
    end

    private

    def next_submission_id
      submission_id = Dway.bioproject[:submission].reverse(:submission_id).get(:submission_id) || "PSUB000000"
      num           = submission_id.delete_prefix("PSUB").to_i

      "PSUB#{num.succ.to_s.rjust(6, '0')}"
    end

    def modify_xml(doc, project_id, is_public)
      archive_id = doc.at("/PackageSet/Package/Project/Project/ProjectID/ArchiveID")

      archive_id[:accession] = project_id
      archive_id[:archive]   = "DDBJ"

      if is_public
        doc.at("/PackageSet/Package/Submission/Submission/Description/Hold")&.remove

        if release_date = doc.at("/PackageSet/Package/Project/Project/ProjectDescr/ProjectReleaseDate")
          if release_date.text.empty?
            release_date.content = Time.current.iso8601
          end
        else
          # TODO: Error handling
        end
      end

      doc
    end

    def submission_data_attrs(submission, submission_id, doc)
      [
        *doc.xpath("/PackageSet/Package/Submission/Submission/Description/Organization/Contact").flat_map.with_index(1) { |contact, i|
          first_name = contact.at("Name/First")
          last_name  = contact.at("Name/Last")
          email      = contact[:email]
          
          [
            [ "submitter", "first_name.#{i}", first_name&.text, i ],
            [ "submitter", "last_name.#{i}",  last_name&.text,  i ],
            [ "submitter", "email.#{i}",      email,            i ]
          ]
        },

        doc.at("/PackageSet/Package/Submission/Submission/Description/Organization/Name").then {
          [ "submitter", "organization_name", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Submission/Submission/Description/Organization/@url").then {
          [ "submitter", "organization_url", _1&.text, -1 ]
        },

        [ "submitter", "data_release", submission.visibility_public? ? "nonhup" : "hup", -1 ],

        doc.at("/PackageSet/Package/Project/Project/ProjectDescr/Title").then {
          [ "general_info", "project_title", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectDescr/Description").then {
          [ "general_info", "public_description", _1&.text, -1 ]
        },

        *doc.xpath("/PackageSet/Package/Project/Project/ProjectDescr/ExternalLink").flat_map.with_index(1) { |link, i|
          url = link.at("URL")

          [
            [ "general_info", "link_description.#{i}", link[:label], i ],
            [ "general_info", "link_url.#{i}",         url&.text,    i ]
          ]
        },

        *doc.xpath("/PackageSet/Package/Project/Project/ProjectDescr/Grant").flat_map.with_index(1) { |grant, i|
          agency = grant.at("Agency")
          abbr   = grant.at("Agency/@abbr")
          title  = grant.at("Title")

          [
            [ "general_info", "agency.#{i}",              agency&.text,    i ],
            [ "general_info", "agency_abbreviation.#{i}", abbr&.text,      i ],
            [ "general_info", "grant_id.#{i}",            grant[:GrantId], i ],
            [ "general_info", "grant_title.#{i}",         title&.text,     i ]
          ]
        },

        *doc.xpath("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/ProjectDataTypeSet/DataType").flat_map.with_index(1) { |data_type, i|
          if value = PROJECT_DATA_TYPES[data_type.text]
            [
              [ "project_type", "project_data_type", value, i ]
            ]
          else
            [
              [ "project_type", "project_data_type",             "other",        i ],
              [ "project_type", "project_data_type_description", data_type.text, i ]
            ]
          end
        },

        *doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target").then {
          [
            [ "project_type", "sample_scope", _1&.[](:sample_scope), -1 ],
            [ "project_type", "material",     _1&.[](:material),     -1 ],
            [ "project_type", "capture",      _1&.[](:capture),      -1 ]
          ]
        },

        *doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Method").then {
          method_type = _1&.[](:method_type)
          description = method_type == "eOther" ? _1&.text : nil

          [
            [ "project_type", "methodology",             method_type, -1 ],
            [ "project_type", "methodology_description", description, -1 ]
          ]
        },

        *doc.xpath("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Objectives").map.with_index(1) { |objectives, i|
          data = objectives.at("Data")

          [ "project_type", "objective.#{i}", data&.[](:data_type), i ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/OrganismName").then {
          [ "target", "organism_name", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism").then {
          tax_id = _1&.[](:taxID)

          [ "target", "taxonomy_id", tax_id == "0" ? nil : tax_id, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/Strain").then {
          [ "target", "strain_breed_cultivar", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/Label").then {
          [ "target", "isolate_name_or_label", _1&.text, -1 ]
        },

        *doc.xpath("/PackageSet/Package/Project/Project/ProjectDescr/Publication").map.with_index(1) { |publication, i|
          case publication.at("Reference/DbType")&.text
          when "ePubmed"
            [ "publication", "pubmed_id.#{i}", publication[:id], i ]
          when "eDOI"
            [ "publication", "doi.#{i}", publication[:id], i ]
          else
            raise "Unsupported publication type"
          end
        }
      ].compact.map { |form_name, data_name, data_value, t_order|
        {
          submission_id:,
          form_name:,
          data_name:,
          data_value:,
          t_order:
        }
      }
    end
  end
end
