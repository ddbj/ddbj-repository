namespace :dway do
  # Records that D-way has handed over (DwayTakeover): run at the switch,
  # once registration and curation there have stopped, which only whoever
  # runs it can say (DWAY_STOPPED=yes). From the next night the hold date
  # releases data here, and the import from D-way is refused — the D-way
  # connection with it, so DRA's numbers are taken over first
  # (dra:take_over_numbering), and the last imports have to have finished.
  #
  # Before it: a published DRA submission has to reach the public area
  # from here, which D-way's release did and nothing here does yet.
  #
  #   DWAY_STOPPED=yes TAKEN_OVER_BY=<uid> bin/rails dway:take_over
  desc 'Record that D-way has handed over to this system'
  task take_over: :environment do
    if (done = DwayTakeover.first)
      puts "Taken over at #{done.taken_over_at} by #{done.taken_over_by}."
      next
    end

    abort "Take over DRA's numbers first (dra:take_over_numbering): it reads them from D-way." unless AccessionIssue.dra_taken_over?

    if (running = MigrationRun.where(status: %w[queued running]).pluck(:db)).any?
      abort "Imports from D-way are still under way (#{running.uniq.join(', ')}): let them finish, or abandon them."
    end

    by = ENV['TAKEN_OVER_BY']

    abort 'Say who is taking over, with TAKEN_OVER_BY=<uid> of a curator.' unless User.staff.exists?(uid: by)

    due = HoldDateRelease.new.preview

    puts "The first night will release #{due.projects} BioProject(s) and #{due.dra_submissions} DRA submission(s) whose hold date has passed."

    abort 'Run once D-way takes no registrations and curates nothing, with DWAY_STOPPED=yes.' unless ENV['DWAY_STOPPED'] == 'yes'

    done = DwayTakeover.record!(by:)

    puts "Taken over at #{done.taken_over_at}."
  end
end
