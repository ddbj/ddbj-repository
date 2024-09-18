class BioSample::OperationHistory < BioSample::Record
  self.table_name = "operation_history"

  belongs_to :submission, class_name: "BioSample::Submission", optional: true
end
