# What PublicXML::DRA::Exporter asks to be moved between DRA's public
# tree and the private one it writes into, and what came of it. The
# public tree is D-way's FTP site, written by its account and not by this
# one: `script/dra-mover`, run from cron as that account, carries the
# requests out (see there for the format and what it refuses).
#
# A request is a submission's, and there is one at a time for each: one
# not yet settled — waiting, or carried out and not yet read here — keeps
# the submission from being asked about again, so two cannot cross.
#
#   requests/20261029T040000123456-DRA000123-publish.json   waiting
#   requests/done/…                                        carried out
#   requests/failed/…                                      not, with its error
#   requests/unreadable/…                                  not one of ours
class DRA::PublicationRequests
  Request = Data.define(:accession, :action, :requested_at, :error)

  # A move: :publish (private to public) or :withdraw (public to private),
  # of a path relative to the named tree's root.
  Move = Data.define(:op, :tree, :path)

  # As the mover reads them: DRA's alone, which is all it moves.
  NAME = /\A(?<stamp>\d{8}T\d{12})-(?<accession>DRA\d{6,})-(?<action>publish|withdraw)\.json\z/

  def self.default = new(Pathname.new(Rails.application.config_for(:app).output_dir!).join('private', 'requests'))

  def initialize(root)
    @root = Pathname.new(root)
  end

  attr_reader :root

  # Written whole under a name the mover passes over, then renamed.
  def submit(accession, action, moves, requested_at:)
    name = "#{requested_at.utc.strftime('%Y%m%dT%H%M%S%6N')}-#{accession}-#{action}.json"
    tmp  = @root.join(".#{name}.tmp")

    body = {
      submission:   accession,
      action:       action.to_s,
      requested_at: requested_at.iso8601(6),
      moves:        moves.map { {op: it.op.to_s, tree: it.tree.to_s, path: it.path.to_s} }
    }

    @root.mkpath
    tmp.write JSON.generate(body)
    tmp.rename @root.join(name)
  end

  # The submissions with a request not yet settled.
  def outstanding = [@root, @root.join('done'), @root.join('failed')].flat_map { it.glob('*.json') }.filter_map { NAME.match(it.basename.to_s)&.[](:accession) }.to_set

  # Each request carried out or failed, oldest first, gone once the block
  # returns: what it says is to be recorded by then. Read by its name, which
  # the mover keeps; its body only for the error. What is not named as one
  # of ours is put aside, and yields only an error saying so.
  #
  # What a run stopped while submitting left half written goes first: it
  # was never asked for.
  def each_settled
    @root.glob('.*.json.tmp').each(&:delete)

    %w[done failed].flat_map { @root.join(it).glob('*.json') }.sort_by(&:basename).each do |path|
      if (name = NAME.match(path.basename.to_s))
        yield Request.new(
          accession:    name[:accession],
          action:       name[:action].to_sym,
          requested_at: Time.find_zone('UTC').strptime(name[:stamp], '%Y%m%dT%H%M%S%N').in_time_zone,
          error:        (error_in(path) if path.dirname.basename.to_s == 'failed')
        )

        path.delete
      else
        aside = @root.join('unreadable').tap(&:mkpath).join(path.basename)

        yield Request.new(accession: nil, action: nil, requested_at: nil, error: "#{path.relative_path_from(@root)} is not a request; put aside in #{aside.relative_path_from(@root)}")

        path.rename aside
      end
    end
  end

  private

  def error_in(path)
    JSON.parse(path.read)['error'] || 'failed, saying nothing'
  rescue JSON::ParserError => e
    "failed, and what the mover said is unreadable: #{e.message}"
  end
end
