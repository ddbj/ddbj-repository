class Validation < ApplicationRecord
  belongs_to :user

  has_one :submission, dependent: :restrict_with_exception

  has_many :objs, dependent: :destroy do
    def base
      find { _1._id == '_base' }
    end
  end

  enum :progress, %w(waiting running finished canceled).index_by(&:to_sym)

  scope :validity, -> (*validities) {
    return none if validities.empty?

    sql = validities.map {|validity|
      case validity
      when 'valid'
        <<~SQL
          NOT EXISTS (
            SELECT 1 FROM objs
            WHERE objs.validation_id = validations.id
              AND (objs.validity <> 'valid' OR objs.validity IS NULL)
          )
        SQL
      when 'invalid'
        <<~SQL
          NOT EXISTS (
            SELECT 1 FROM objs
            WHERE objs.validation_id = validations.id
              AND objs.validity = 'error'
          ) AND objs.validity = 'invalid'
        SQL
      when 'error'
        %(objs.validity = 'error')
      when 'null'
        <<~SQL
          NOT EXISTS (
            SELECT 1 FROM objs
            WHERE objs.validation_id = validations.id
              AND (objs.validity <> 'valid' OR objs.validity <> 'invalid' OR objs.validity <> 'error')
          )
        SQL
      else
        raise ArgumentError, validity
      end
    }.join(' OR ')

    joins(:objs).where(sql)
  }

  scope :submitted, -> (submitted) {
    submitted ? where.associated(:submission) : where.missing(:submission)
  }

  validates :db, inclusion: {in: DB.map { _1[:id] }}

  validates :started_at,  presence: true, if: :running?
  validates :finished_at, presence: true, if: ->(validation) { validation.finished? || validation.canceled? }

  def validity
    if objs.all?(&:validity_valid?)
      'valid'
    elsif objs.any?(&:validity_error?)
      'error'
    elsif objs.any?(&:validity_invalid?)
      'invalid'
    else
      nil
    end
  end

  def results
    objs.sort_by(&:id).map(&:validation_result)
  end

  def write_files_to_tmp(&block)
    Dir.mktmpdir {|tmpdir|
      tmpdir = Pathname.new(tmpdir)

      objs.without_base.each do |obj|
        path = tmpdir.join(obj.path)
        path.dirname.mkpath

        obj.file.open do |file|
          FileUtils.mv file.path, path
        end
      end

      block.call tmpdir
    }
  end

  def write_submission_files(to:)
    to.tap(&:mkpath).join('validation-report.json').write JSON.pretty_generate(results)

    objs.each do |obj|
      obj_dir = to.join(obj._id)

      if obj.base?
        obj_dir.mkpath
        obj_dir.join('validation-report.json').write JSON.pretty_generate(obj.validation_result)
      else
        path = obj_dir.join(obj.path)
        path.dirname.mkpath

        obj.file.open do |file|
          FileUtils.mv file.path, path
        end

        File.write "#{path}-validation-report.json", JSON.pretty_generate(obj.validation_result)
      end
    end
  end
end
