using PathnameContain

class Validation < ApplicationRecord
  class UnprocessableContent < StandardError; end

  belongs_to :user

  has_one :submission, dependent: :destroy

  has_many :objs, -> { order(:id) }, dependent: :destroy do
    def base
      find { _1._id == '_base' }
    end
  end

  serialize :raw_result, coder: JSON

  validates :db, inclusion: {in: DB.map { _1[:id] }}

  validates :started_at,  presence: true, if: :running?
  validates :finished_at, presence: true, if: ->(validation) { validation.finished? || validation.canceled? }

  enum :progress, %w[waiting running finished canceled].index_by(&:to_sym)
  enum :via,      %w[file ddbj_record].index_by(&:to_sym), prefix: true

  scope :validity, ->(*validities) {
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

  scope :submitted, ->(submitted) {
    submitted ? where.associated(:submission) : where.missing(:submission)
  }

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

  def build_obj_from_path(relative_path, obj_schema:, destination:, user:)
    template = Rails.application.config_for(:app).mass_dir_path_template!
    mass_dir = Pathname.new(template.gsub('{user}', user.uid))
    path     = mass_dir.join(relative_path)

    raise UnprocessableContent, "path must be in #{mass_dir}" unless mass_dir.contain?(path)

    build_obj = ->(obj_schema, path, destination) {
      objs.build(
        _id: obj_schema[:id],

        file: {
          io:       path.open,
          filename: path.basename
        },

        destination:
      )
    }

    begin
      if obj_schema[:multiple] && path.directory?
        path.glob('**/*').reject(&:directory?).each do |fpath|
          destination = [
            destination,
            fpath.relative_path_from(path).dirname.to_s
          ].reject { _1.blank? || _1 == '.' }.join('/').presence

          build_obj.call(obj_schema, fpath, destination)
        end
      else
        build_obj.call(obj_schema, path, destination)
      end
    rescue Errno::ENOENT
      raise UnprocessableContent, "path does not exist: #{path}"
    rescue Errno::EISDIR
      raise UnprocessableContent, "path is directory: #{path}"
    end
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
