module DDBJRecord
  Qualifier = Data.define(
    :id,
    :value
  )

  LocalizedText = Data.define(
    :language_code,
    :text
  )

  Address = Data.define(
    :country,
    :state,
    :city,
    :street,
    :postal_code
  )

  Organization = Data.define(
    :name,
    :abbreviation,
    :url,
    :role,
    :type,
    :department,
    :address,
    :ror_id
  )

  Person = Data.define(
    :name,
    :abbreviation,
    :email,
    :orcid,
    :organization
  )

  Xref = Data.define(
    :db,
    :id
  )

  Reference = Data.define(
    :title,
    :authors,
    :consortiums,
    :status,
    :year,
    :journal,
    :volume,
    :issue,
    :start_page,
    :end_page,
    :date_published,
    :doi,
    :url,
    :pubmed_id
  )

  ApplicationIdentification = Data.define(
    :filing_date,
    :ip_office_code,
    :application_number_text
  )

  Submission = Data.define(
    :submitters,
    :db_xrefs,
    :references,
    :comments,
    :trad_submission_category,
    :division,
    :locus_tag_prefix,
    :seq_prefix,
    :hold_date,
    :keywords,
    :datatype,

    # ST.26 extensions
    :publication_date,
    :applicant_name,
    :inventor_name,
    :invention_title,
    :application_identification,
    :earliest_priority_application_identifications
  )

  Provenance = Data.define(
    :source_format,
    :extras
  )

  LibraryLayout = Data.define(
    :layout_type,
    :nominal_length,
    :nominal_sdev
  )

  TargetedLocus = Data.define(
    :locus_name,
    :description
  )

  Platform = Data.define(
    :platform_type,
    :instrument_model
  )

  Design = Data.define(
    :design_description,
    :library_name,
    :library_strategy,
    :library_source,
    :library_selection,
    :library_layout,
    :targeted_loci,
    :pooling_strategy,
    :library_construction_protocol
  )

  Experiment = Data.define(
    :id,
    :title,
    :design,
    :platform,
    :experiment_attributes
  )

  St26 = Data.define(
    :applicant_names,
    :applicant_name_latin,
    :inventor_names,
    :inventor_name_latin,
    :invention_titles
  )

  Source = Data.define(
    :organism,
    :mol_type,
    :qualifiers
  )

  SourceFeature = Data.define(
    :id,
    :location,
    :source,
    :definition
  )

  Entry = Data.define(
    :id,
    :name,
    :type,
    :topology,
    :sequence,
    :comments,
    :source_features,

    # server extension fields
    :length,
    :definition,
    :tax_id,
    :accession,
    :locus,
    :version,
    :last_updated
  )

  Feature = Data.define(
    :id,
    :type,
    :location,
    :sequence_id,
    :qualifiers,
    :locus_tag_id
  )

  Sequences = Data.define(
    :common_source,
    :entries
  )

  Root = Data.define(
    :schema_version,
    :provenance,
    :submission,
    :experiments,
    :st26,
    :sequences,
    :features
  )

  # Dispatch on `schema_version`. v2 streams through SAJ (memory bound by the
  # largest single entry — see CLAUDE.md / streaming_parser.rb); v3 currently
  # buffers the full document because V3::Parser is non-streaming. The IO
  # must be rewindable so the detector's head-peek does not steal the v2
  # streaming path.
  #
  # The v3 path returns a `DDBJRecord::V3::Root`, which is structurally
  # distinct from `DDBJRecord::Root`. As of Phase 2, downstream consumers
  # (DDBJRecordValidator, RegenerateSubmissionFlatfilesJob, the flatfile
  # template) still expect the v2 shape and will raise `NoMethodError` on
  # v3 input. No production producer emits v3 yet; consumer porting is
  # tracked in Phase 3 of tmp/data-migration/implementation-plan.md.
  def self.parse(io)
    unless io.respond_to?(:rewind)
      raise ArgumentError, "DDBJRecord.parse requires a rewindable IO; got #{io.class}"
    end

    major, _head = SchemaVersionDetector.detect(io)
    io.rewind

    case major
    when '2' then Handler.new.tap { Oj.saj_parse(it, io) }.result
    when '3' then V3::Parser.parse(io.read)
    end
  end

  def self.generate(record)
    file = Tempfile.open(['ddbj_record', '.json'])
    file.binmode

    Writer.new(file).write record

    file.write "\n"
    file.rewind

    file
  end
end
