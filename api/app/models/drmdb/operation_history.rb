class DRMDB::OperationHistory < DRMDB::Record
  self.table_name         = "operation_history"
  self.inheritance_column = nil

  enum :type, {
    info: 3
  }
end
