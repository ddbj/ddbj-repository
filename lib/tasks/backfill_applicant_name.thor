# vim: ft=ruby

require_relative '../../config/environment'

class BackfillApplicantNameTasks < Thor
  namespace :backfill_applicant_name

  FALLBACK = 'Applicants [Refer to the patent publication]'.freeze

  def self.exit_on_failure? = true

  desc 'execute', 'Fill empty applicant_name with placeholder on existing DDBJ Records'
  method_option :dry_run, type: :boolean, default: false, aliases: '-n', desc: 'Report targets without writing'
  def execute
    scope = Submission.where.associated(:ddbj_record_attachment).includes(:request)
    count = 0

    scope.find_each do |submission|
      labels = [
        [:submission, submission],
        [:request,    submission.request]
      ].filter_map {|label, record|
        label if patch!(record, dry_run: options[:dry_run])
      }

      next if labels.empty?

      count += 1
      prefix = options[:dry_run] ? '[dry-run] Would patch' : 'Patched'

      say "#{prefix} submission_id=#{submission.id} targets=[#{labels.join(', ')}]"
    end

    say "Done. #{count} submission(s) #{options[:dry_run] ? 'matched' : 'patched'}."
  end

  private

  def patch!(record, dry_run:)
    attachment = record.ddbj_record
    parsed     = JSON.parse(attachment.download, symbolize_names: true)

    return false if parsed.dig(:submission, :applicant_name).present?
    return true  if dry_run

    parsed[:submission][:applicant_name] = FALLBACK

    record.update!(ddbj_record: {
      io:           StringIO.new(JSON.generate(parsed)),
      filename:     attachment.filename.to_s,
      content_type: attachment.content_type
    })

    true
  end
end
