class BioProject::Project < BioProject::Record
  self.table_name = 'project'

  belongs_to :submission, class_name: 'BioProject::Submission'

  enum :status_id, {
    private: 5400,
    public:  5500
  }, prefix: true
end
