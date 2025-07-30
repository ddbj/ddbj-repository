class BioSample::Link < BioSample::Record
  self.table_name = 'link'

  belongs_to :sample, class_name: 'BioSample::Sample', foreign_key: 'smp_id'
end
