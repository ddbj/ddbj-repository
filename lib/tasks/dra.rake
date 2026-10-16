namespace :dra do
  # Reads a run's reads as the check before accessions will (DRA::ReadCheck),
  # from files a user has uploaded and not yet assigned — picked by name, as a
  # record will pick them. For trying SRA Toolkit on real reads until
  # submissions reach it themselves.
  #
  #   bin/rails 'dra:check_reads[alice,fastq,ILLUMINA,run1_R1.fastq.gz,run1_R2.fastq.gz]'
  #   bin/rails 'dra:check_reads[alice,sra,,DRR000001.sra]'
  desc "Read a user's uploaded reads with SRA Toolkit"
  task :check_reads, %i[uid filetype platform] => :environment do |_, args|
    user  = User.find_by!(uid: args[:uid])
    names = args.extras

    abort 'Name the files to read.' if names.empty?

    blobs = names.map {|name|
      user.unassigned_files.blobs.find_by(filename: name) or abort "#{args[:uid]} has no unassigned file named #{name}."
    }

    result = DRA::ReadCheck.call(files: blobs, filetype: args[:filetype], platform: args[:platform].presence)

    puts result.output

    # Taken, as D-way took it, can still have dropped records the loader
    # could not read.
    verdict =
      if !result.ok?
        'Refused.'
      elsif result.errors.any?
        "Read, with #{result.errors.size} error line(s) above: records may have been dropped."
      else
        'Read.'
      end

    puts verdict
  end

  # Takes DRA's numbering over from D-way: each prefix the repository issues
  # (AccessionIssue) continues from the last D-way issued, read from drmdb.
  #
  # Only once D-way issues no DRA number of any kind — not for new
  # submissions, and not for the ones still in it below accession issued,
  # which a curator there would otherwise go on numbering: D-way takes
  # `max(acc_no) + 1` of its own and never sees ours, so the same number
  # would come from both. Said by whoever runs it (DWAY_DRA_STOPPED=yes),
  # since drmdb cannot: it lists those still in it to be sure about.
  # Run before DRA is opened here (`record_dbs`), which issuing waits for.
  #
  # Run again at any time, it checks: D-way having issued past where it was
  # taken over is a collision, and it stops saying so.
  #
  #   DWAY_DRA_STOPPED=yes bin/rails dra:take_over_numbering
  desc "Continue DRA's accession numbers from where D-way stopped"
  task take_over_numbering: :environment do
    client = DRA::StagingClient.new

    # Which D-way this is: read from the wrong one — a stale copy — the
    # numbers would start below what D-way has issued.
    puts "Reading D-way's DRA numbers from #{client.source_fingerprint.slice('database', 'server_addr', 'server_port').values.join(' ')}"

    last   = client.last_accession_numbers
    scopes = AccessionIssue.dra_scopes

    # All of them, before anything is written: one missing would leave the
    # others taken over and it not, with nothing to take it over from.
    missing = scopes.map(&:upcase) - last.keys

    abort "drmdb has no #{missing.join(', ')} numbers; is this D-way's database?" if missing.any?

    Sequence.ensure_records!

    first = scopes.any? { !Sequence.find_by!(scope: it).taken_over? }

    if first && ENV['DWAY_DRA_STOPPED'] != 'yes'
      waiting = client.enumerate_excluded.count { it.reason == 'in_progress' }

      abort <<~MESSAGE
        D-way still has #{waiting} DRA submission(s) below accession issued. Once DRA's numbering is
        taken over, D-way must issue no DRA number of any kind, theirs included. When it does not,
        run again with DWAY_DRA_STOPPED=yes.
      MESSAGE
    end

    Sequence.transaction do
      scopes.each do |scope|
        prefix   = scope.upcase
        number   = last.fetch(prefix)
        sequence = Sequence.find_by!(scope:)

        case sequence.continue_after!(number)
        when :taken_over then puts "#{prefix}: taken over after D-way's #{number}; continuing from #{sequence.peek}"
        when :unchanged  then puts "#{prefix}: D-way has issued nothing since #{number}; next is #{sequence.peek}"
        end
      end
    end
  rescue Sequence::Collision => e
    abort "COLLISION — #{e.message}. The same numbers have been issued by both; stop D-way issuing DRA numbers and find them."
  rescue Sequence::WrongSource => e
    abort "#{e.message}. This is not the database it was taken over from."
  ensure
    client&.close
  end

  # Renders the public XML of every DRA submission that is public, or that
  # its hold date will make public (HoldDateRelease), and checks it against
  # the version it is written in, writing nothing: how many PublishDRAXMLJob
  # would refuse, and how many will be kept private, and why. For the
  # D-way records — before the tree is first written from here, and before
  # D-way hands over (`dway:take_over`), after which those it still holds
  # are checked for the first time as their dates come.
  #
  #   bin/rails dra:check_public_xml
  desc 'Check that every public or releasable DRA submission renders as valid SRA XML'
  task check_public_xml: :environment do
    {
      'public'                => DRASubmission.status_public,
      'released by hold date' => DRASubmission.where(status: HoldDateRelease::RELEASABLE_FROM).where.not(hold_date: nil)
    }.each do |label, rows|
      refused = Hash.new {|hash, key| hash[key] = [] }
      checked = 0

      rows.where.not(accession: nil).includes(:submission).find_each do |row|
        checked += 1

        PublicXML::DRA::Documents.call(row.submission.materialised_record)
      rescue PublicXML::DRA::Documents::Invalid, Submission::MaterialisationFailed => e
        refused[e.message.sub(/\A(\w+: [^.]*).*/m, '\1')] << row.accession
      end

      puts "#{label}: #{checked} checked, #{refused.values.sum(&:size)} refused."

      refused.sort_by { -_2.size }.each do |reason, accessions|
        puts "  #{accessions.size}\t#{reason}\t#{accessions.first(5).join(' ')}"
      end
    end
  end
end
