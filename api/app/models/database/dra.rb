module Database::DRA
  class Validator
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
            'BUNDLE_GEMFILE' => Rails.root.join('Gemfile').to_s
          }

          out, status = Open3.capture2e(env, *%w(bundle exec validate_meta_dra -a example -i 0001 --machine-readable))

          raise out unless status.success?

          errors = JSON.parse(out, symbolize_names: true).group_by { _1.fetch(:object_id) }

          validation.objs.without_base.group_by(&:_id).each do |obj_id, objs|
            if errs = errors[obj_id]
              objs.each do |obj|
                obj.validity_invalid!

                errs.each do |err|
                  obj.validation_details.create!(
                    severity: 'error',
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

  class Submitter
    def submit(submission)
      db = Sequel.connect(ENV.fetch('DRA_DATABASE_URL'))

      user_id      = 42
      submitter_id = '42'

      db.transaction auto_savepoint: true do
        serial = nil
        sub_id = nil

        db.transaction isolation: :serializable do
          serial = (db[:submission].where(submitter_id:).max(:serial) || 0) + 1

          sub_id = db[:submission].insert(
            usr_id:       user_id,
            submitter_id: ,
            serial:       ,
            create_date:  Date.current
          )
        end

        submission_id = "#{submitter_id}-#{serial.to_s.rjust(4, '0')}"

        db[:status_history].insert(
          sub_id: ,
          status: 100 # SubmissionStatus.NEW
        )

        db[:operation_history].insert(
          type:         3, # LogLevel.INFO
          summary:      'Status update to new',
          usr_id:       user_id,
          serial:       ,
          submitter_id:
        )

        ext_id = db[:ext_entity].insert(
          acc_type: 'DRA',
          ref_name: submission_id,
          status:   0 # ExtStatus.INPUTTING
        )

        db[:ext_permit].insert(
          ext_id:       ,
          submitter_id:
        )
      end
    end
  end
end
