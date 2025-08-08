Rails.application.config.after_initialize do
  Sequence.ensure_records!
end
