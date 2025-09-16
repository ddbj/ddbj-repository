using PathnameContain

class Obj < ApplicationRecord
  belongs_to :validation

  has_many :validation_details, -> { order(:id) }, dependent: :destroy

  has_one_attached :file

  scope :without_base, -> { where.not(_id: '_base') }

  enum :_id, DB.flat_map { _1[:objects] }.map { _1[:id] }.uniq.concat(['_base']).index_by(&:to_sym)
  enum :validity, %w[valid invalid error].index_by(&:to_sym), prefix: true

  validate :destination_must_not_be_malformed
  validate :path_must_be_unique_in_request

  def base? = _id == '_base'

  def path
    return nil if base?

    [destination, file.filename.sanitized].compact_blank.join('/')
  end

  def validation_result
    {
      object_id: _id,
      validity:  validity,

      details: validation_details.map {
        _1.slice(:code, :severity, :message).symbolize_keys
      },

      file: base? ? nil : {
        path:,
        url:  Rails.application.routes.url_helpers.validation_file_url(validation, path)
      }
    }
  end

  private

  def destination_must_not_be_malformed
    return if base?
    return unless destination

    tmp = Pathname.new('/tmp').join(SecureRandom.uuid)

    errors.add :destination, 'is malformed path' unless tmp.contain?(tmp.join(destination))
  end

  def path_must_be_unique_in_request
    return if base?

    if validation.objs.to_a.without(self).any? { path == it.path }
      errors.add :path, "is duplicated: #{path}"
    end
  end
end
