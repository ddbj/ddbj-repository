class DRMDB::SubmissionComponent < DRMDB::Record
  self.table_name = 'submission_component'

  belongs_to :submission_group, class_name: 'DRMDB::SubmissionGroup', foreign_key: 'grp_id', primary_key: 'grp_id'
end
