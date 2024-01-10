class PassthroughValidator
  def validate(request)
    request.objs.without_base.each &:validity_valid!
  end
end
