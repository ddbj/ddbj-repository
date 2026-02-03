using PathnameContain

class Validation < ApplicationRecord
  class UnprocessableContent < StandardError; end

  belongs_to :subject, polymorphic: true

  has_many :details, dependent: :destroy, class_name: 'ValidationDetail'

  serialize :raw_result, coder: JSON

  validates :finished_at, presence: true, if: ->(validation) { validation.finished? || validation.canceled? }

  enum :progress, %w[running finished canceled].index_by(&:to_sym), validate: true

  scope :submitted, ->(submitted) {
    submitted ? where.associated(:submission) : where.missing(:submission)
  }

  scope :with_validity, -> {
    left_joins(:details).group(:id).select('validations.*', <<~SQL)
      CASE
        WHEN validations.progress != 'finished'                                    THEN NULL
        WHEN COUNT(CASE WHEN validation_details.severity = 'error' THEN 1 END) = 0 THEN 'valid'
        ELSE 'invalid'
      END AS validity
    SQL
  }

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

    subject.objs.each do |obj|
      obj_dir = to.join(obj._id)

      if obj._base?
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
