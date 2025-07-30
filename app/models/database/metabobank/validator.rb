class Database::MetaboBank::Validator
  def validate(validation)
    objs = validation.objs.without_base.index_by(&:_id)

    validation.write_files_to_tmp do |tmpdir|
      Dir.chdir tmpdir do
        idf, sdrf = objs.fetch_values('IDF', 'SDRF').map(&:path)

        cmd = %W[bundle exec mb-validate --machine-readable -i #{idf} -s #{sdrf}].then {
          if bs = objs['BioSample']
            _1 + %W[-t #{bs.path}]
          else
            _1
          end
        }.then {
          if objs.key?('MAF') || objs.key?('RawDataFile') || objs.key?('ProcessedDataFile')
            _1 + %w[-d]
          else
            _1
          end
        }

        out, status = Open3.capture2e({
          'BUNDLE_GEMFILE' => Rails.root.join('Gemfile').to_s
        }, *cmd)

        raise out unless status.success?

        errors = JSON.parse(out, symbolize_names: true).group_by { _1.fetch(:object_id) }

        validation.objs.without_base.group_by(&:_id).each do |obj_id, objs|
          if errs = errors[obj_id]
            validity = if errs.any? { _1[:severity] == 'error' }
                         'invalid'
            else
                         'valid'
            end

            objs.each do |obj|
              obj.update! validity: validity

              errs.each do |err|
                obj.validation_details.create! err.slice(:code, :severity, :message)
              end
            end
          else
            objs.each do |obj|
              obj.validity_valid!
            end
          end
        end
      end
    end
  end
end
