class BioSample::OperationHistory < BioSample::Record
  self.table_name         = 'operation_history'
  self.inheritance_column = nil

  belongs_to :submission, class_name: 'BioSample::Submission', optional: true

  enum :type, {
    debug: 0,
    info:  1,
    warn:  2,
    error: 3,
    fatal: 4
  }
end
