module PublicXML
  module DRA
    # The public tree of DRA, as D-way's release laid it out on the FTP
    # site (DRA::ReadsTree): a directory a submission, under one named by
    # the first six characters of its accession, holding a document a kind
    # beside its reads —
    #
    #   fastq/DRA000/DRA000368/DRA000368.submission.xml
    #                          DRA000368.experiment.xml …
    #                          DRX000001/DRR000001_1.fastq.bz2 …
    #   sra/ByExp/sra/DRX/DRX000/DRX000001/DRR000001/DRR000001.sra
    #
    # The documents are written here; the files (DRA::SubmissionFiles) are
    # moved in from the private tree they were built into, before them, and
    # back out to it when it leaves public, after them — D-way's too, which
    # are here from the start.
    #
    # BioProject and BioSample are one file each, written whole; DRA is a
    # tree of tens of thousands of submissions, so a run writes those whose
    # documents are not in it as they stand — never written, or published
    # since (`last_published_at`: a first publication, a public record
    # whose public view changed, D-way's import) — and takes out those no
    # longer public.
    #
    # Which those are is kept half in the tree and half in the database,
    # since either can be lost without the other: each row says when its
    # documents were written (`public_xml_written_at`), and the tree when
    # the last run in it began (MARKER). A row written after that was
    # written into another tree — one standing in for this while it was not
    # mounted — and is written again; a tree with no marker is written
    # whole (#mark!).
    #
    # A submission that cannot be written (a document not valid, its record
    # unreadable) is reported on the run and left as it was, to be tried
    # again by the next run; the others are written all the same. A run
    # stopped part way leaves its rows written, so the next goes on from
    # there.
    #
    # The tree is not only ours: D-way's is where its SRA mirror put
    # NCBI's and EBI's submissions too (SRA…, ERA…), and the reads beside
    # them are petabytes. So a run touches only the directories of
    # submissions it has rows for, and never walks the tree.
    class Exporter
      MARKER = '.last_run'

      # `tree` the public one, `withheld` where files wait to be published.
      def initialize(tree: ::DRA::ReadsTree.at(:public), withheld: ::DRA::ReadsTree.at(:private), started_at: Time.current)
        @tree       = tree
        @withheld   = withheld
        @output_dir = tree.root.join('fastq')
        @started_at = started_at
      end

      def call
        @output_dir.mkpath

        mark!

        run     = PublicXMLRun.create!(db: 'dra', kind: 'public', status: 'running', started_at: @started_at)
        emitted = 0
        refused = []

        due.includes(:submission).find_each do |row|
          if (refusal = write(row))
            refused << "#{row.accession}: #{refusal}"
          else
            emitted += 1
          end
        end

        refused.concat withdraw

        run.append_error!(refused.join("\n"))
        run.update!(status: 'completed', emitted:, finished_at: Time.current)

        Rails.error.report(Refused.new("#{refused.size} DRA submissions could not be published; see public XML run #{run.id}"), handled: true) if refused.any?

        run
      rescue StandardError => e
        if run
          run.append_error!("#{e.class}: #{e.message}\n#{e.backtrace.first(20).join("\n")}")
          run.update!(status: 'failed', finished_at: Time.current)
        end

        raise
      end

      class Refused < StandardError; end

      private

      def published = DRASubmission.status_public.where.not(accession: nil)

      # What the tree is missing, said in the database before the tree's
      # marker moves on: every row, for a tree with no marker; those
      # written after its last run began — into another tree — otherwise.
      # Said there, a run stopped part way leaves the next to go on from
      # where it was.
      def mark!
        marker   = @output_dir.join(MARKER)
        last_run = (Time.zone.parse(marker.read) if marker.exist?)

        missing = last_run ? published.where('dra_submissions.public_xml_written_at > ?', last_run) : published
        missing.update_all public_xml_written_at: nil

        marker.write @started_at.iso8601(6)
      end

      def due = published.where(public_xml_written_at: nil).or(published.where('dra_submissions.last_published_at > dra_submissions.public_xml_written_at'))

      # Nil once written; what stood in the way otherwise. A fault of the
      # tree's own (the disk) is the run's, and ends it.
      def write(row)
        return "not an accession of DRA's" unless row.accession.match?(DRASubmission::ACCESSION_FORMAT)

        directory = @tree.submission_dir(row.accession)

        # What a run stopped between writing and renaming a document left
        # of it: the row stayed due, so this is where it is cleared — refused
        # this time or not.
        partials = ::DRA::XMLRenderer::KINDS.map { directory.join("#{row.accession}.#{it}.xml.partial") }
        FileUtils.rm_f partials

        record    = row.submission.materialised_record
        documents = Documents.call(record)
        files     = ::DRA::SubmissionFiles.new(row.accession, record)

        # Built here, every run has its .sra: one with none is filed
        # elsewhere than it was built (its experiment changed since).
        if row.submission.source_id.nil? && (missing = files.missing_sras(@withheld, @tree)).any?
          return "its reads are not where they were built: #{missing.join(', ')}"
        end

        files.move from: @withheld, to: @tree
        directory.mkpath

        documents.each do |kind, xml|
          partial = directory.join("#{row.accession}.#{kind}.xml.partial")

          partial.write xml
          partial.rename directory.join("#{row.accession}.#{kind}.xml")
        end

        # A kind the record no longer has objects of.
        (::DRA::XMLRenderer::KINDS - documents.keys).each do |kind|
          FileUtils.rm_f directory.join("#{row.accession}.#{kind}.xml")
        end

        row.update_column :public_xml_written_at, @started_at

        nil
      rescue SystemCallError, IOError
        raise
      rescue Documents::Invalid, Submission::MaterialisationFailed => e
        e.message
      rescue StandardError => e
        "#{e.class}: #{e.message}"
      end

      # What has left public (suppressed, withdrawn) is taken out of the
      # tree, as D-way's runbook took it out by hand — by its row, whether
      # this tree or D-way's wrote it: a directory of a submission there is
      # no row for is the mirror's, not this run's to take. Its files go
      # back to the private tree, kept to be published again, then its
      # documents; the directory goes once nothing else is in it.
      #
      # A row is taken out if it was ever public, or written; never public,
      # what is there is D-way's, whose status this may be behind. Its row
      # is no longer written — whenever it comes back and however D-way's
      # import dates that — once its documents are gone, so a run stopped
      # part way takes them out again. What could not be, its record
      # unreadable, says why.
      def withdraw
        withdrawn = DRASubmission.where.not(id: published.select(:id)).where.not(accession: nil).merge(
          DRASubmission.where.not(first_published_at: nil).or(DRASubmission.where.not(public_xml_written_at: nil))
        )

        refused = {}

        withdrawn.includes(:submission).find_each do |row|
          next unless row.accession.match?(DRASubmission::ACCESSION_FORMAT)

          directory = @tree.submission_dir(row.accession)

          next unless directory.directory?

          begin
            ::DRA::SubmissionFiles.new(row.accession, row.submission.materialised_record).move from: @tree, to: @withheld
          rescue Submission::MaterialisationFailed => e
            refused[row.id] = "#{row.accession}: not taken out, its files not known: #{e.message}"

            next
          end

          documents = ::DRA::XMLRenderer::KINDS.flat_map { [directory.join("#{row.accession}.#{it}.xml"), directory.join("#{row.accession}.#{it}.xml.partial")] }

          FileUtils.rm_f documents

          begin
            directory.rmdir
          rescue Errno::ENOENT, Errno::ENOTEMPTY, Errno::ENOTDIR
            # Not only ours.
          end
        end

        # Not one left in the tree, which the next run is to try again.
        withdrawn.where.not(id: refused.keys).where.not(public_xml_written_at: nil).update_all(public_xml_written_at: nil)

        refused.values
      end
    end
  end
end
