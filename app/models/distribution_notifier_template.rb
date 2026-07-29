# Curator-editable subject / body for the DistributionNotifier release
# notice. Single row; `instance` falls back to the built-in defaults so the
# mail works before anyone customises it.
class DistributionNotifierTemplate < ApplicationRecord
  PLACEHOLDER = '%{accessions}'

  # One entry of the accession list: what is being released, when, and the
  # link to the submission where the submitter can reach a curator. The
  # curator writes the prose around it; we own the list itself so both mail
  # parts can render it (plain text / linked markup).
  Notice = Data.define(:accession, :hold_date, :url) do
    def self.for(project)
      new(
        accession: project.accession,
        hold_date: project.hold_date,
        url:       WebApp.url_for("/requests/#{project.submission.request.id}")
      )
    end

    def to_line
      "- #{accession} will be released on #{hold_date.iso8601}\n  #{url}"
    end
  end

  DEFAULT_SUBJECT = '[DDBJ Repository] Your data will be released soon'

  DEFAULT_BODY = <<~BODY.strip
    Dear submitter,

    Your specified hold date is approaching and the following data will be
    released on the date shown.

    #{PLACEHOLDER}

    If you need to change a release date, open the submission from the link
    next to it and message the DDBJ curator from there.

    Regards,
    DDBJ Repository
  BODY

  validates :subject, presence: true
  validates :body,    presence: true
  validate  :body_keeps_accessions_placeholder

  def self.instance
    first || new(subject: DEFAULT_SUBJECT, body: DEFAULT_BODY)
  end

  # Text body: the placeholder replaced by the plain-text accession list.
  def render_body(notices)
    # Block form so backslash sequences in the list (URLs) aren't treated
    # as gsub replacement references.
    body.gsub(PLACEHOLDER) { notices.map(&:to_line).join("\n") }
  end

  # The body split around the placeholder, so the html part can render the
  # accession list as markup — a plain-text URL isn't reliably clickable.
  # The blank lines that separate the list in the text body are stripped;
  # in html the list is its own block already.
  def body_around_placeholder
    before, after = body.split(PLACEHOLDER, 2)

    [before.to_s.strip, after.to_s.strip]
  end

  private

  # Without the placeholder the mail would silently omit the accessions.
  def body_keeps_accessions_placeholder
    return if body.blank? || body.include?(PLACEHOLDER)

    errors.add(:body, "must contain the #{PLACEHOLDER} placeholder")
  end
end
