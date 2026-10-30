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
    # The tree is not written here. It is D-way's, written by the account
    # its release ran as, and the SRA mirror puts NCBI's and EBI's
    # submissions in it too (SRA…, ERA…) — petabytes, which this reads
    # (mounted read-only) but never walks. What is to be published is
    # written into the private tree beside it instead, laid out the same,
    # where the submission's reads were built (BuildDRAReadsJob), and moved
    # across by `script/dra-mover`, run as that account, on a request
    # (::DRA::PublicationRequests): the documents after the files they
    # describe. What has left public is moved back by the same means,
    # documents first, to be published again.
    #
    # BioProject and BioSample are one file each, written whole; DRA is a
    # tree of tens of thousands of submissions, so a run asks only for those
    # whose documents are not in it as they stand — never published, or
    # published since (`last_published_at`: a first publication, a public
    # record whose public view changed, D-way's import), or gone from it —
    # and for those no longer public to be taken out.
    #
    # Each row says when what was asked for it was published
    # (`public_xml_written_at`): when its request was made, recorded once
    # the mover has carried it out — the run after, which reads what came
    # of each. One failed is reported on that run and asked for again; one
    # not yet carried out keeps the submission out of the run, so two
    # requests cannot cross. A submission that cannot be written (a
    # document not valid, its record unreadable) is reported on the run and
    # left as it was, to be tried again by the next; the others are asked
    # for all the same.
    class Exporter
      TREE = :dra

      # What the mover moves. The 27 of D-way's numbered SRA, in a tree with
      # NCBI's SRA… beside them, are left as they are, and one of them
      # leaving public is said for a person to take out.
      MOVED = /\ADRA\d{6,}\z/

      Move = ::DRA::PublicationRequests::Move

      # `tree` the public one, `withheld` the private one beside it.
      def initialize(tree: ::DRA::ReadsTree.at(:public), withheld: ::DRA::ReadsTree.at(:private), requests: ::DRA::PublicationRequests.default, started_at: Time.current)
        @tree       = tree
        @withheld   = withheld
        @requests   = requests
        @started_at = started_at
      end

      def call
        run     = PublicXMLRun.create!(db: 'dra', kind: 'public', status: 'running', started_at: @started_at)
        settled = settle
        waiting = @requests.outstanding
        refused = []
        emitted = 0

        # Said at once: the requests they came of are gone.
        run.append_error!(settled.join("\n"))

        published.find_each do |row|
          next if waiting.include?(row.accession) || !row.accession.match?(MOVED) || !due?(row)

          if (refusal = write(row))
            refused << "#{row.accession}: #{refusal}"
          else
            waiting << row.accession
            emitted += 1
          end
        end

        refused.concat withdraw(waiting)

        run.append_error!(refused.join("\n"))
        run.update!(status: 'completed', emitted:, finished_at: Time.current)

        if (count = settled.size + refused.size).positive?
          Rails.error.report(Refused.new("#{count} DRA submissions could not be published or taken out; see public XML run #{run.id}"), handled: true)
        end

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

      # What the mover did with the last run's requests. A publication
      # carried out dates its row by when it was asked for, so one
      # published again since is due again; a withdrawal leaves its row
      # unwritten. One that failed leaves the row as it was, so the run
      # asks again — what is to be done about it said on the run.
      #
      # D-way's import clears the date too, for a version of its own; one
      # landing between a request and this would be lost under it. It does
      # not: the import stops at the handover (DwayTakeover), before which
      # nothing is asked for.
      def settle
        refused = []

        @requests.each_settled do |request|
          if request.accession.nil?
            refused << request.error
          elsif request.error
            refused << "#{request.accession}: not #{request.action == :publish ? 'published' : 'taken out'}: #{request.error}"
          else
            DRASubmission.where(accession: request.accession).update_all public_xml_written_at: (request.requested_at if request.action == :publish)
          end
        end

        refused
      end

      # Its documents are not in the tree as they stand: never published,
      # published since, or gone — taken out by hand, or the tree restored
      # from before. Its submission's document says so, or for a record
      # with none, any other.
      def due?(row)
        row.public_xml_written_at.nil? ||
          (row.last_published_at && row.last_published_at > row.public_xml_written_at) ||
          ::DRA::XMLRenderer::KINDS.none? { document(@tree, row.accession, it).file? }
      end

      def document(tree, accession, kind) = tree.submission_dir(accession).join("#{accession}.#{kind}.xml")

      # Nil once asked for; what stood in the way otherwise. A fault of the
      # private tree's own (the disk) is the run's, and ends it.
      def write(row)
        return "not an accession of DRA's" unless row.accession.match?(DRASubmission::ACCESSION_FORMAT)

        directory = @withheld.submission_dir(row.accession)

        # What a run stopped between writing and renaming a document left
        # of it: the row stayed due, so this is where it is cleared —
        # refused this time or not.
        FileUtils.rm_f ::DRA::XMLRenderer::KINDS.map { directory.join("#{row.accession}.#{it}.xml.partial") }

        record    = row.submission.materialised_record
        documents = Documents.call(record)
        files     = ::DRA::SubmissionFiles.new(row.accession, record)

        # Built here, every run has its .sra: one with none is filed
        # elsewhere than it was built (its experiment changed since).
        if row.submission.source_id.nil? && (missing = files.missing_sras(@withheld, @tree)).any?
          return "its reads are not where they were built: #{missing.join(', ')}"
        end

        directory.mkpath

        documents.each do |kind, xml|
          partial = directory.join("#{row.accession}.#{kind}.xml.partial")

          # Writable by its owner alone, as the mover takes only such a file
          # public.
          partial.write xml
          partial.chmod ::DRA::ReadsTree::FILE_MODE
          partial.rename document(@withheld, row.accession, kind)
        end

        # A kind the record no longer has objects of: one left here from
        # before is not to go out, and one out there is to come back.
        stale = ::DRA::XMLRenderer::KINDS - documents.keys

        FileUtils.rm_f stale.map { document(@withheld, row.accession, it) }

        moves = [
          *files.paths(@withheld).map { Move.new(op: :publish, tree: TREE, path: it) },
          *documents.keys.map { Move.new(op: :publish, tree: TREE, path: document(@withheld, row.accession, it).relative_path_from(@withheld.root)) },
          *stale.map { document(@tree, row.accession, it) }.select(&:file?).map { Move.new(op: :withdraw, tree: TREE, path: it.relative_path_from(@tree.root)) }
        ]

        @requests.submit row.accession, :publish, moves, requested_at: @started_at

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
      # no row for is the mirror's, not this run's to take. Its documents
      # go back to the private tree first, then its files, kept to be
      # published again: its runs' .sra before what is in its directory,
      # which goes last, so one stopped part way is still there to be taken
      # out by the next run.
      #
      # A row is taken out if it was ever public, or written; never public,
      # what is there is D-way's, whose status this may be behind. One with
      # nothing there is no longer written, whenever it comes back and
      # however D-way's import dates that. What could not be asked for, its
      # record unreadable, says why.
      def withdraw(waiting)
        withdrawn = DRASubmission.where.not(id: published.select(:id)).where.not(accession: nil).merge(
          DRASubmission.where.not(first_published_at: nil).or(DRASubmission.where.not(public_xml_written_at: nil))
        )

        refused = []
        gone    = []

        withdrawn.find_each do |row|
          next if waiting.include?(row.accession) || !row.accession.match?(DRASubmission::ACCESSION_FORMAT)

          # Its files are found from its record, which is not worth reading
          # for each of the thousands already out.
          unless @tree.submission_dir(row.accession).directory?
            gone << row.id

            next
          end

          unless row.accession.match?(MOVED)
            refused << "#{row.accession}: numbered SRA, which the mover does not take out; to be taken out by hand"

            next
          end

          documents = ::DRA::XMLRenderer::KINDS.map { document(@tree, row.accession, it) }.select(&:file?)

          begin
            files = ::DRA::SubmissionFiles.new(row.accession, row.submission.materialised_record).paths(@tree)
          rescue Submission::MaterialisationFailed => e
            refused << "#{row.accession}: not taken out, its files not known: #{e.message}"

            next
          end

          moves = (documents.map { it.relative_path_from(@tree.root) } + files).map { Move.new(op: :withdraw, tree: TREE, path: it) }

          if moves.empty?
            gone << row.id
          else
            @requests.submit row.accession, :withdraw, moves, requested_at: @started_at
          end
        end

        DRASubmission.where(id: gone).where.not(public_xml_written_at: nil).update_all public_xml_written_at: nil

        refused
      end
    end
  end
end
