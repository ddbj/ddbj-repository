module DDBJRecord
  Qualifier = Data.define(
    :id,
    :value
  )

  LocalizedText = Data.define(
    :language_code,
    :text
  )

  ApplicationIdentification = Data.define(
    :filing_date,
    :ip_office_code,
    :application_number_text
  )

  Submission = Data.define(
    :application_identification,
    :division,
    :earliest_priority_application_identifications
  )

  St26 = Data.define(
    :applicant_names,
    :applicant_name_latin,
    :inventor_names,
    :inventor_name_latin,
    :invention_titles
  )

  Entry = Data.define(
    :id,
    :sequence,
    :length,
    :location,
    :topology,
    :definition,
    :tax_id,
    :source_qualifiers
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
    :entries
  )

  Root = Data.define(
    :schema_version,
    :submission,
    :st26,
    :sequences,
    :features
  )
end
