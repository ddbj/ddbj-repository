class BioSample::Attribute < BioSample::Record
  self.table_name = 'attribute'

  belongs_to :sample, class_name: 'BioSample::Sample', foreign_key: 'smp_id'
end
