module DDBJRecord
  Qualifier = Data.define(
    :id,
    :value
  ) { include DataExtensions }

  LocalizedText = Data.define(
    :language_code,
    :text
  ) { include DataExtensions }

  ApplicationIdentification = Data.define(
    :filing_date,
    :ip_office_code,
    :application_number_text
  ) { include DataExtensions }

  Submission = Data.define(
    :application_identification,
    :division,
    :earliest_priority_application_identifications,
    :publication_date,
    :applicant_name,
    :invention_title,
    :inventor_name
  ) { include DataExtensions }

  St26 = Data.define(
    :applicant_names,
    :applicant_name_latin,
    :inventor_names,
    :inventor_name_latin,
    :invention_titles
  ) { include DataExtensions }

  Entry = Data.define(
    :id,
    :sequence,
    :length,
    :location,
    :topology,
    :definition,
    :tax_id,
    :source_qualifiers,
    :accession,
    :locus,
    :version,
    :last_updated
  ) { include DataExtensions }

  Feature = Data.define(
    :id,
    :type,
    :location,
    :sequence_id,
    :qualifiers,
    :locus_tag_id
  ) { include DataExtensions }

  Sequences = Data.define(
    :entries
  ) { include DataExtensions }

  Root = Data.define(
    :schema_version,
    :submission,
    :st26,
    :sequences,
    :features
  ) { include DataExtensions }

  def self.parse(io)
    Handler.new.tap { Oj.saj_parse(it, io) }.result
  end
end
