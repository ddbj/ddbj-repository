module Database::BioProject
  class Param
    def self.build(params)
      BioProjectSubmissionParam.new(params.require(:param).permit(:umbrella))
    end
  end

  class Validator
    include DDBJValidator

    def translate_error(error)
      message     = error.fetch(:message)
      annotations = error.fetch(:annotation, []).index_by { _1.fetch(:key) }

      case error.fetch(:id)
      when "BP_R0002"
        xsd_message = annotations.fetch("XSD error message").fetch(:value)

        "#{message} #{xsd_message}"
      else
        message
      end
    end
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

        project_id = Dway.bioproject[:project].insert(
          submission_id:,
          project_type:  "primary",
          status_id:     is_public ? BP_PROJECT_STATUS_ID_PUBLIC : BP_PROJECT_STATUS_ID_PRIVATE,
          release_date:  is_public ? Sequel.function(:now)       : nil,
          dist_date:     is_public ? Sequel.function(:now)       : nil,
          modified_date: Sequel.function(:now)
        )

        content = submission.validation.objs.find_by!(_id: "BioProject").file.download
        doc     = Nokogiri::XML.parse(content)
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
      user              = submission.validation.user
      organization_name = [ user.department, user.organization ].compact_blank.join(", ")

      [
        [ "submitter", "first_name",        user.first_name,                                    1 ],
        [ "submitter", "last_name",         user.last_name,                                     1 ],
        [ "submitter", "email",             user.email,                                         1 ],
        [ "submitter", "organization_name", organization_name,                                  -1 ],
        [ "submitter", "organization_url",  user.organization_url,                              -1 ],
        [ "submitter", "data_release",      submission.visibility_public? ? "nonhup" : "hup",   -1 ],

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

        doc.at("/PackageSet/Package/Project/Project/ProjectDescr/Relevance").then {
          next nil unless _1

          if other = _1.at("Other")
            [ "general_info", "relevance_description", other.text, -1 ]
          else
            [ "general_info", "relevance", _1.childeren.first.name, -1 ]
          end
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Provider").then {
          [ "general_info", "biomaterial_provider", _1&.text, -1 ]
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

        doc.at("/PackageSet/Package/Project/Project/ProjectDescr/LocusTagPrefix").then {
          [ "project_type", "locus_tag", _1&.text, -1 ]
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

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Morphology/Gram").then {
          [ "target", "prokaryote_gram", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Morphology/Enveloped").then {
          [ "target", "prokaryote_enveloped", _1&.text, -1 ]
        },

        *doc.xpath("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Morphology/Shape").map.with_index(1) { |shape, i|
          [ "target", "prokaryote_shape.#{i}", shape.text, i ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Morphology/Endospores").then {
          [ "target", "prokaryote_endospores", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Morphology/Motility").then {
          [ "target", "prokaryote_motility", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Environment/Salinity").then {
          [ "target", "environment_salinity", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Environment/OxygenReq").then {
          [ "target", "environment_oxygen_requirement", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Environment/OptimumTemperature").then {
          [ "target", "environment_optimum_temperature", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Environment/TemperatureRange").then {
          [ "target", "environment_temperature_range", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Environment/Habitat").then {
          [ "target", "environment_habitat", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Phenotype/BioticRelationship").then {
          [ "target", "phenotype_biotic_relationship", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Phenotype/TrophicLevel").then {
          [ "target", "phenotype_trophic_level", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/BiologicalProperties/Phenotype/Disease").then {
          [ "target", "phenotype_disease", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/Organization").then {
          [ "target", "cellularity", _1&.text, -1 ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/Reproduction").then {
          [ "target", "reproduction", _1&.text, -1 ]
        },

        *doc.xpath("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/RepliconSet/Replicon").flat_map.with_index(1) { |replicon, i|
          type        = replicon.at("Type")
          name        = replicon.at("Name")
          size        = replicon.at("Size")
          description = replicon.at("Description")

          [
            [ "target", "replicons_order.#{i}",                replicon[:order],              i ],
            [ "target", "replicons_location.#{i}",             type&.[](:location),           i ],
            [ "target", "replicons_type_description.#{i}",     type&.[](:typeOtherDescr),     i ],
            [ "target", "replicons_location_description.#{i}", type&.[](:locationOtherDescr), i ],
            [ "target", "replicons_type.#{i}",                 type&.text,                    i ],
            [ "target", "replicons_name.#{i}",                 name&.text,                    i ],
            [ "target", "replicons_size_unit.#{i}",            size&.[](:units),              i ],
            [ "target", "replicons_size.#{i}",                 size&.text,                    i ],
            [ "target", "replicons_description.#{i}",          description&.text,             i ]
          ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/RepliconSet/Ploidy").then {
          [ "target", "ploidy", _1&.[](:type), -1 ]
        },

        *doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Organism/GenomeSize").then {
          [
            [ "target", "haploid_genome_size_unit", _1&.[](:units), -1 ],
            [ "target", "haploid_genome_size",      _1&.text,       -1 ]
          ]
        },

        doc.at("/PackageSet/Package/Project/Project/ProjectType/ProjectTypeSubmission/Target/Description").then {
          [ "target", "label_description", _1&.text, -1 ]
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
