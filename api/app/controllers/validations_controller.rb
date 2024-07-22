class ValidationsController < ApplicationController
  include Pagy::Backend

  def index
    validations = search_validations

    pagy, @validations = pagy(validations, page: params[:page])

    pagy_headers_merge pagy
  rescue Pagy::OverflowError => e
    render json: {
      error: e.message
    }, status: :bad_request
  end

  def show
    @validation = eager_load(accessible_validations).find(params[:id])
  end

  def destroy
    validation = accessible_validations.find(params[:id])

    if validation.finished? || validation.canceled?
      render json: {
        error: "Validation has been #{validation.progress}."
      }, status: :unprocessable_entity
    else
      validation.update! progress: 'canceled', finished_at: Time.current

      render json: {
        message: 'Validation canceled successfully.'
      }
    end
  end

  private

  def accessible_validations
    current_user.admin? ? Validation.all : current_user.validations
  end

  def search_validations
    everyone, uid, db, created_at_after, created_at_before, progress, validity, submitted = params.values_at(:everyone, :uid, :db, :created_at_after, :created_at_before, :progress, :validity, :submitted)

    validations = current_user.admin? && everyone == 'true' ? Validation.all : current_user.validations

    validations = validations.joins(:user).where(user: {uid: uid.split(',')})           if current_user.admin? && uid
    validations = validations.where(db: db.split(','))                                  if db
    validations = validations.where(created_at: created_at_after..created_at_before)    if created_at_after || created_at_before
    validations = validations.where(progress: progress.split(','))                      if progress
    validations = validations.validity(*validity.split(','))                            if validity
    validations = validations.submitted(ActiveModel::Type::Boolean.new.cast(submitted)) if submitted

    eager_load(validations).order(id: :desc)
  end

  def eager_load(validations)
    validations.includes(:user, :submission, :objs => :validation_details).merge(Obj.with_attached_file)
  end
end
