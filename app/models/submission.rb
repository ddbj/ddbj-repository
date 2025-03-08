class Submission < ApplicationRecord
  belongs_to :validation

  delegated_type :param, types: %w[BioProjectSubmissionParam], optional: true, dependent: :destroy

  validates :validation_id, uniqueness: { message: "is already submitted" }

  validate :validation_must_be_valid
  validate :validation_finished_at_must_be_in_24_hours

  enum :progress,   %w[waiting running finished canceled].index_by(&:to_sym)
  enum :result,     %w[success failure].index_by(&:to_sym)
  enum :visibility, %w[public private].index_by(&:to_sym), prefix: true

  after_destroy do |submission|
    submission.dir.rmtree
  end

  def to_param  = public_id
  def public_id = id ? "X-#{id}" : nil

  def dir
    base = Rails.application.config_for(:app).repository_dir!

    Pathname.new(base).join(validation.user.uid, "submissions", public_id)
  end

  private

  def validation_must_be_valid
    unless validation.validity == "valid"
      errors.add :validation, "must be valid"
    end
  end

  def validation_finished_at_must_be_in_24_hours
    if validation.validity == "valid" && validation.finished_at <= 1.day.ago
      errors.add :validation, "finished_at must be in 24 hours"
    end
  end
end
