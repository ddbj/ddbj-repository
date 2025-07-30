class BioSample::Sample < BioSample::Record
  self.table_name = 'sample'

  belongs_to :submission, class_name: 'BioSample::Submission', foreign_key: 'submission_id'

  has_many :_attributes, class_name: 'BioSample::Attribute', foreign_key: 'smp_id'
  has_many :links,       class_name: 'BioSample::Link',      foreign_key: 'smp_id'
  has_many :xmls,        class_name: 'BioSample::XML',       foreign_key: 'smp_id'

  enum :release_type, {
    release: 1,
    hold:    2
  }

  enum :status_id, {
    new_submission:      5000,
    submission_accepted: 5100,
    curating:            5200,
    biosample_id_issue:  5300,
    private:             5400,
    public:              5500,
    killed:              5600,
    cancel:              5700,
    suppressed:          5800
  }, prefix: true
end
