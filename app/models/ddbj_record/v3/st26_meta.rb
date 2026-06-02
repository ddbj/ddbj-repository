module DDBJRecord
  module V3
    St26Meta = Data.define(
      :dtd_version,
      :software_name,
      :software_version,
      :production_date,
      :original_language,
      :non_english_language,
      :applicant_file_reference,
      :applicant_name,
      :applicant_name_latin,
      :inventor_name,
      :inventor_name_latin,
      :application,
      :earliest_priority,
      :invention_titles
    )
  end
end
