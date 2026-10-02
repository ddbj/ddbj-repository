# What applying a request does, by its database: the pipeline around it —
# the request's status, its error code — is ApplySubmissionRequestJob's, the
# same for every database; what a record becomes is each database's own.
module SubmissionApply
  APPLIERS = {
    'st26'       => 'St26',
    'bioproject' => 'BioProjectRecord',
    'biosample'  => 'BioSampleRecord'
  }.freeze

  # The databases whose records can be applied here: a request for any
  # other could be checked, and then sent to fail.
  def self.dbs = APPLIERS.keys

  def self.for(db)
    APPLIERS.fetch(db) { raise ArgumentError, "#{db} records are not applied yet" }.then { const_get(it) }
  end
end
