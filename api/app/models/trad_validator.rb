class TradValidator
  EXT = {
    'Sequence'   => %w(.fasta .seq.fa .fa .fna .seq),
    'Annotation' => %w(.ann .annt.tsv .ann.txt)
  }

  def validate(request)
    objs = request.objs.without_base

    objs.each do |obj|
      obj.validation_details = []
    end

    validate_ext      objs
    validate_pairwise objs
    validate_seq      objs
    validate_ann      objs

    objs.each do |obj|
      if obj.validation_details.empty?
        obj.update! validity: 'valid', validation_details: nil
      else
        obj.validity_invalid!
      end
    end
  end

  private

  def validate_ext(objs)
    objs.each do |obj|
      expected = EXT.fetch(obj._id)

      unless expected.any? { obj.path.end_with?(_1) }
        obj.validation_details << {
          severity: 'error',
          message:  "The extension should be one of the following: #{expected.join(', ')}"
        }
      end
    end
  end

  def validate_pairwise(objs)
    pairs = objs.group_by {|obj|
      expected = EXT.fetch(obj._id)
      ext      = expected.find { obj.path.end_with?(_1) }

      ext ? obj.path.delete_suffix(ext) : obj.path.sub(/\..+?\z/, '')
    }

    pairs.each do |basename, objs|
      objs_by_id = objs.group_by(&:_id)

      anns = objs_by_id['Annotation'] || []
      seqs = objs_by_id['Sequence']   || []

      case anns.size
      when 0
        seqs.each do |seq|
          seq.validation_details << {
            severity: 'error',
            message:  'There is no corresponding annotation file.'
          }
        end
      when 1
        # do nothing
      else
        anns.each do |ann|
          ann.validation_details << {
            severity: 'error',
            message:  'Duplicate annotation files with the same name exist.'
          }
        end
      end

      case seqs.size
      when 0
        anns.each do |ann|
          ann.validation_details << {
            severity: 'error',
            message:  'There is no corresponding sequence file.'
          }
        end
      when 1
        # do nothing
      else
        seqs.each do |seq|
          seq.validation_details << {
            severity: 'error',
            message:  'Duplicate sequence files with the same name exist.'
          }
        end
      end
    end
  end

  def validate_seq(objs)
    objs.select { _1._id == 'Sequence' }.each do |obj|
      unless contain_at_least_one_entry_in_seq?(obj.file)
        obj.validation_details << {
          severity: 'error',
          message:  'No entries found.'
        }
      end
    end
  end

  def validate_ann(objs)
    anns = objs.select { _1._id == 'Annotation' }

    return if anns.empty?

    assoc = anns.map {|obj|
      contact_person = extract_contact_person_in_ann(obj.file)

      if contact_person.values.any?(&:nil?)
        obj.validation_details << {
          severity: 'error',
          message:  'Contact person information (contact, email, institute) is missing.'
        }
      end

      [obj, contact_person]
    }

    _, first_contact_person = assoc.first

    assoc.each do |obj, contact_person|
      unless first_contact_person == contact_person
        obj.validation_details << {
          severity: 'error',
          message:  'Contact person must be the same for all annotation files.'
        }
      end
    end
  end

  def contain_at_least_one_entry_in_seq?(file)
    bol = true

    file.download do |chunk|
      return true if bol && chunk.start_with?('>')
      return true if /[\r\n]>/.match?(chunk)

      bol = chunk.end_with?("\r", "\n")
    end

    false
  end

  def extract_contact_person_in_ann(file)
    in_common   = false
    full_name   = nil
    email       = nil
    affiliation = nil

    file.download.each_line chomp: true do |line|
      break if full_name && email && affiliation

      entry, _feature, _location, qualifier, value = line.split("\t")

      break if in_common && entry.present?

      in_common = entry == 'COMMON' if entry.present?

      next unless in_common

      case qualifier
      when 'contact'
        full_name = value
      when 'email'
        email = value
      when 'institute'
        affiliation = value
      else
        # do nothing
      end
    end

    {
      full_name:,
      email:,
      affiliation:
    }
  end
end
