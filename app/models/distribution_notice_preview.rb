# The release notice as a submitter will receive it, rendered from real
# candidates.
#
# The template screen used to explain `%{accessions}` in a paragraph above
# the textarea. A worked example of the same thing, side by side with the
# field being edited, says it without the prose — and catches the case the
# prose cannot, which is a body that reads fine and expands wrong.
class DistributionNoticePreview
  def initialize(template, projects)
    @template = template
    @projects = Array(projects)
  end

  attr_reader :template

  def available? = @projects.any?

  def user = @projects.first&.submission&.user

  def to = user&.email

  def subject = template.subject

  # Split around the placeholder so the screen can mark where the list
  # lands — which is the one part of the mail the curator does not write.
  def before = parts.first

  def after = parts.last

  def notices
    @notices ||= @projects.map { DistributionNotifierTemplate::Notice.for(it) }
  end

  private

  def parts = @parts ||= template.body_around_placeholder
end
