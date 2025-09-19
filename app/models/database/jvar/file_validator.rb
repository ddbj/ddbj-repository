class Database::JVar::FileValidator
  def validate(validation)
    validation.objs.without_base.each(&:validity_valid!)
  end
end
