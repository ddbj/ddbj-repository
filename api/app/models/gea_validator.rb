class GeaValidator
  def validate(validation)
    objs = validation.objs.without_base.index_by(&:_id)

    validation.write_files_to_tmp do |tmpdir|
      Dir.chdir tmpdir do
        idf, sdrf = objs.fetch_values('IDF', 'SDRF').map(&:path)

        cmd = %W(bundle exec mb-validate --machine-readable -i #{idf} -s #{sdrf}).then {
          if objs.key?('RawDataFile') || objs.key?('ProcessedDataFile')
            _1 + %w(-d)
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
            objs.each do |obj|
              obj.update! validity: 'valid', validation_details: errs
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
