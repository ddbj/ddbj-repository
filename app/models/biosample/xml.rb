class BioSample::XML < BioSample::Record
  self.table_name = "xml"

  belongs_to :sample, class_name: "BioSample::Sample", foreign_key: "smp_id"
end
