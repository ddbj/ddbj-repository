class Submission < ApplicationRecord
  belongs_to :request

  after_destroy do |submission|
    submission.dir.rmtree
  end

  def to_param  = public_id
  def public_id = id ? "X-#{id}" : nil

  def dir
    Pathname.new(ENV.fetch('REPOSITORY_DIR')).join(request.user.uid, 'submissions', public_id)
  end
end
