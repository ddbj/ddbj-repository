# Curator-editable subject / body for the DistributionNotifier release
# notice. Single row; `instance` falls back to the built-in defaults so the
# mail works before anyone customises it.
class DistributionNotifierTemplate < ApplicationRecord
  PLACEHOLDER = '%{accessions}'

  DEFAULT_SUBJECT = '[DDBJ Repository] Your data will be released soon'

  DEFAULT_BODY = <<~BODY.strip
    Dear submitter,

    Your specified hold date is approaching and the following data will be
    released on the date shown. If you need to change a release date, please
    open the submission and contact the DDBJ curator through its messages.

    #{PLACEHOLDER}

    Regards,
    DDBJ Repository
  BODY

  validates :subject, presence: true
  validates :body,    presence: true
  validate  :body_keeps_accessions_placeholder

  def self.instance
    first || new(subject: DEFAULT_SUBJECT, body: DEFAULT_BODY)
  end

  # Substitute the accessions placeholder with the per-project list. Each
  # line carries the accession, its release date, and a link to the
  # submission.
  def render_body(projects:, web_url:)
    list = projects.map {|project|
      url = URI.join(web_url, "/web/requests/#{project.submission.request.id}").to_s

      "- #{project.accession} will be released on #{project.hold_date.iso8601}\n  #{url}"
    }.join("\n")

    # Block form so backslash sequences in the list (URLs) aren't treated
    # as gsub replacement references.
    body.gsub(PLACEHOLDER) { list }
  end

  private

  # Without the placeholder the mail would silently omit the accessions.
  def body_keeps_accessions_placeholder
    return if body.blank? || body.include?(PLACEHOLDER)

    errors.add(:body, "must contain the #{PLACEHOLDER} placeholder")
  end
end
