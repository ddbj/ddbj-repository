class Database::DRA::Validator
  def validate(validation)
    objs = validation.objs.without_base.index_by(&:_id)

    Dir.mktmpdir do |tmpdir|
      tmpdir = Pathname.new(tmpdir)

      objs.values.each do |obj|
        next unless obj

        obj.file.open do |file|
          FileUtils.mv file.path, tmpdir.join("example-0001_dra_#{obj._id}.xml")
        end
      end

      Dir.chdir tmpdir do
        env = {
          "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s
        }

        out, status = Open3.capture2e(env, *%w[bundle exec validate_meta_dra -a example -i 0001 --machine-readable])

        raise out unless status.success?

        errors = JSON.parse(out, symbolize_names: true).group_by { _1.fetch(:object_id) }

        validation.objs.without_base.group_by(&:_id).each do |obj_id, objs|
          if errs = errors[obj_id]
            objs.each do |obj|
              obj.validity_invalid!

              errs.each do |err|
                obj.validation_details.create!(
                  severity: "error",
                  message:  err.fetch(:message)
                )
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
