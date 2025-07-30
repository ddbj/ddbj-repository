module TradValidation
  def validate_ext(objs, assoc)
    objs.each do |obj|
      exts = assoc.fetch(obj._id)

      unless exts.any? { obj.path.end_with?(_1) }
        obj.validation_details.create!(
          severity: 'error',
          message:  "The extension should be one of the following: #{exts.join(', ')}"
        )
      end
    end
  end

  def validate_nwise(objs, assoc)
    objs.group_by {|obj|
      exts = assoc.fetch(obj._id)
      ext  = exts.find { obj.path.end_with?(_1) }

      ext ? obj.path.delete_suffix(ext) : obj.path.sub(/\..+?\z/, '')
    }.each do |basename, objs|
      objs_by_id = objs.group_by(&:_id)

      assoc.keys.each do |id|
        objs       = objs_by_id[id] || []
        other_objs = objs_by_id.values_at(*assoc.keys.without(id)).flatten.compact

        case objs.size
        when 0
          other_objs.each do |obj|
            obj.validation_details.create!(
              severity: 'error',
              message:  "There is no corresponding #{id.downcase} file."
            )
          end
        when 1
          # do nothing
        else
          objs.each do |obj|
            obj.validation_details.create!(
              severity: 'error',
              message:  "Duplicate #{id.downcase} files with the same name exist."
            )
          end
        end
      end
    end
  end

  def validate_seq(objs)
    objs.select { _1._id == 'Sequence' }.each do |obj|
      unless contain_at_least_one_entry_in_seq?(obj.file)
        obj.validation_details.create!(
          severity: 'error',
          message:  'No entries found.'
        )
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
end
