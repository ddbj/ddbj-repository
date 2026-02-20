# frozen_string_literal: true

module Flatfile::Helper
  module_function

  def mol_type_label(mol_type)
    case mol_type
    when / RNA\z/
      'RNA'
    when /\A[mtr]RNA\z/
      mol_type
    when 'viral cRNA'
      'cRNA'
    else
      'DNA'
    end
  end

  def format_date(date)
    return nil unless date

    date.to_date.strftime('%d-%^b-%Y')
  end

  def format_seqid(seqid, format: :default)
    seqid => {country_code:, document_number:, kind_code:, sequence_number:}

    separator = {
      default: '/',
      journal: ' '
    }.fetch(format)

    "#{country_code} #{document_number}-#{kind_code}#{separator}#{sequence_number}"
  end

  def format_qualifier(qual)
    qual => {key:, value:}

    if value
      qual.need_quote? ? %(/#{key}="#{value}") : "/#{key}=#{value}"
    else
      "/#{key}"
    end
  end

  def base_count(seq)
    h         = seq.chars.tally
    h.default = 0

    %w[a c g t].map {|k|
      "#{h[k].to_s.rjust(11)} #{k}"
    }.join('  ')
  end
end
