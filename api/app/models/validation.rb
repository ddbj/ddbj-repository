class Validation < ApplicationRecord
  belongs_to :user

  has_one :submission, dependent: :restrict_with_exception

  has_many :objs, dependent: :destroy do
    def base
      find { _1._id == '_base' }
    end
  end

  enum :progress, %w(waiting processing finished canceled).index_by(&:to_sym)

  validates :db, inclusion: {in: DB.map { _1[:id] }}

  validates :started_at,  presence: true, if: :processing?
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
    objs.map(&:validation_result)
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
