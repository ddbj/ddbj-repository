module SearchValidations
  def search_validations_for_user(validations)
    db, created_at_after, created_at_before, progress, validity, submitted = params.values_at(:db, :created_at_after, :created_at_before, :progress, :validity, :submitted)

    validations = validations.where(db: db.split(','))                                  if db
    validations = validations.where(created_at: created_at_after..created_at_before)    if created_at_after || created_at_before
    validations = validations.where(progress: progress.split(','))                      if progress
    validations = validations.validity(*validity.split(','))                            if validity
    validations = validations.submitted(ActiveModel::Type::Boolean.new.cast(submitted)) if submitted

    validations.order(id: :desc)
  end

  def search_validations_for_admin(validations)
    uid = params[:uid]

    validations = search_validations_for_user(validations)
    validations = validations.joins(:user).where(user: {uid: uid.split(',')}) if uid

    validations
  end
end
