class Database::JVar::Validator
  def validate(validation)
    validation.objs.without_base.each(&:validity_valid!)
  end
end
