# What applying a request does, by its database: the pipeline around it —
# the request's status, its error code — is ApplySubmissionRequestJob's, the
# same for every database; what a record becomes is each database's own.
module SubmissionApply
  def self.for(db)
    case db
    when 'st26' then St26
    else raise ArgumentError, "#{db} records are not applied yet"
    end
  end
end
