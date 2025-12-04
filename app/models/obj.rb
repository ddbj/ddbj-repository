using PathnameContain

class Obj < ApplicationRecord
  belongs_to :owner, polymorphic: true

  has_many :validation_details, -> { order(:id) }, dependent: :destroy

  has_one_attached :file

  enum :_id, DB.flat_map { it[:objects].values.flatten }.pluck(:id).uniq.concat(['_base']).index_by(&:to_sym)

  scope :without_base, -> { where.not(_id: '_base') }

  scope :with_validity, -> {
    left_joins(validation_details: :validation).group(:id).select('objs.*', <<~SQL)
      CASE
        WHEN validations.progress != 'finished'                                    THEN NULL
        WHEN COUNT(CASE WHEN validation_details.severity = 'error' THEN 1 END) = 0 THEN 'valid'
        ELSE 'invalid'
      END AS validity
    SQL
  }

  validates :file, attached: true, unless: :_base?

  validate :destination_must_not_be_malformed
  validate :path_must_be_unique_in_request

  def self.base
    find { it._base? }
  end

  def validity
    validation_details.exists?(severity: 'error') ? 'invalid' : 'valid'
  end

  def path
    return nil if _base?

    [destination, file.filename.sanitized].compact_blank.join('/')
  end

  def validation_result
    {
      object_id: _id,
      validity:  validity,
      details:   validation_details.map { it.slice(:entry_id, :code, :severity, :message).symbolize_keys },

      file: _base? ? nil : {
        path:,
        url:  Rails.application.routes.url_helpers.validation_file_url(validation, path)
      }
    }
  end

  private

  def destination_must_not_be_malformed
    return if _base?
    return unless destination

    tmp = Pathname.new('/tmp').join(SecureRandom.uuid)

    errors.add :destination, 'is malformed path' unless tmp.contain?(tmp.join(destination))
  end

  def path_must_be_unique_in_request
    return if _base?

    if owner.objs.to_a.without(self).any? { path == it.path }
      errors.add :path, "is duplicated: #{path}"
    end
  end
end
