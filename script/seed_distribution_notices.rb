# Development data for the Distribution notices screen.
#
# The screen only says anything when embargoed BioProjects are inside the
# notice window, which real dev data almost never is — a re-import leaves
# it empty again. This builds the shape the design is drawn against: two
# submitters who can be mailed, one who cannot, and enough history for the
# Sent tab and the "blocked since" line to have something to show.
#
#   ruby script/seed_distribution_notices.rb
#
# Idempotent: re-running resets the same records rather than adding more.

require_relative '../config/environment'

abort 'Refusing to seed outside development.' unless Rails.env.development?

SEED_SOURCE_PREFIX = 'PSUB-seed-'

SUBMITTERS = [
  {
    uid:      'yamada@nig',
    email:    'yamada@nig.ac.jp',
    projects: [
      {accession: 'PRJDB19882', title: 'Soil metagenome survey, Hokkaido 2019', in_days: 4},
      {accession: 'PRJDB19901', title: 'Aquatic metagenome survey, Lake Biwa',  in_days: 9}
    ]
  },
  {
    uid:      'kimura@nig',
    email:    'kimura@nig.ac.jp',
    projects: [
      {accession: 'PRJDB19770', title: 'Rice cultivar resequencing', in_days: 7},
      {accession: 'PRJDB19771', title: 'Rice pathogen isolates',     in_days: 7}
    ]
  },
  {
    # No address on file — the case the BLOCKED strip exists for. Nothing
    # is sent and the row stays in Due now until an address turns up.
    uid:      't-yamada',
    email:    nil,
    projects: [
      {accession: 'PRJDB19654', title: 'Marine sediment metagenome', in_days: 8}
    ]
  }
].freeze

# --- clear anything an earlier run left ------------------------------------

previous = Submission.where('source_id LIKE ?', "#{SEED_SOURCE_PREFIX}%")

Project.where(submission_id: previous.select(:id)).delete_all
SubmissionRequest.where(submission_id: previous.select(:id)).delete_all
previous.delete_all

DistributionNotice.where(user_id: User.where(uid: SUBMITTERS.map { it[:uid] }).select(:id)).delete_all

# --- build ------------------------------------------------------------------

SUBMITTERS.each_with_index do |spec, i|
  user = User.find_or_create_by!(uid: spec[:uid])
  user.update!(email: spec[:email])

  spec[:projects].each_with_index do |attrs, j|
    submission = Submission.create!(
      db:        :bioproject,
      user:      user,
      source_id: "#{SEED_SOURCE_PREFIX}#{i}#{j}"
    )

    # Every submission carries a request; the importer mints a synthetic
    # one for migrated records and so does this.
    submission.ensure_migration_request!(migration_run_id: SecureRandom.uuid)

    Project.create!(
      submission:              submission,
      project_type:            :primary,
      status:                  :private,
      accession:               attrs[:accession],
      title:                   attrs[:title],
      hold_date:               Date.current + attrs[:in_days],
      distribution_notified_at: nil
    )
  end
end

# --- history ----------------------------------------------------------------

blocked = User.find_by!(uid: 't-yamada')

# Back-dated so "blocked since" has a number worth reacting to.
DistributionNotice.create!(
  user:        blocked,
  sent_at:     29.days.ago,
  trigger:     :scheduled,
  result:      :skipped,
  skip_reason: DistributionNotice::NO_ADDRESS,
  accessions:  %w[PRJDB19654]
)

DistributionNotice.create!(
  user:       User.find_by!(uid: 'yamada@nig'),
  sent_at:    12.days.ago,
  trigger:    :scheduled,
  result:     :delivered,
  accessions: %w[PRJDB19540 PRJDB19541 PRJDB19544]
)

DistributionNotice.create!(
  user:       User.find_by!(uid: 'kimura@nig'),
  sent_at:    2.days.ago,
  trigger:    :manual,
  actor:      "admin:#{User.staff.order(:uid).first&.uid || 'curator'}",
  result:     :delivered,
  accessions: %w[PRJDB19602]
)

puts "Due now:   #{DistributionNotifier.new.candidates.count} project(s) across #{SUBMITTERS.size} submitter(s)"
puts "Sent:      #{DistributionNotice.count} notice(s)"
puts "Blocked:   #{SUBMITTERS.count { it[:email].nil? }} submitter(s) with no address"
