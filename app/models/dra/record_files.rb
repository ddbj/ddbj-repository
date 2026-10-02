# The files a DRA record's runs and analyses name, each matched to the file
# its submitter uploaded for it: by name, among the uploader's unassigned
# files, and then by MD5, which the record states and the store computed
# when the upload was verified — so matching reads nothing.
#
# The files are uploaded before the record is sent (CLAUDE.md, "Data file
# uploads"), and wait among the uploader's unassigned files until a
# submission is assigned them. Both checking a record (RecordIntake) and
# applying it ask this, so the two cannot disagree on which file is whose —
# and since the one reads the record as sent and the other as kept, names
# are compared as the record keeps them (canonical-json.md §2, the
# single-line class: NFC, whitespace collapsed), on both sides.
#
# One upload is one run's or analysis's file: named twice, it would be
# assigned twice.
class DRA::RecordFiles
  # One FILE of the record: where it is (`runs[0]`), what it says, and the
  # upload it names — or why there is none.
  Entry = Data.define(:list, :index, :object, :file, :blob, :problem) do
    def where    = "#{list}[#{index}]"
    def filename = file['filename']
    def matched? = !blob.nil?
  end

  LISTS = %w[runs analyses].freeze

  # The string class a FILE's name is kept in.
  NAME_CLASS = DDBJRecord::Canonicalizer::PathClassifier.string_class('/runs/0/data_blocks/0/files/0/filename')

  def self.normalise(name)
    DDBJRecord::Canonicalizer::StringNormalizer.normalize(name, NAME_CLASS)
  rescue DDBJRecord::Canonicalizer::Error
    name
  end

  def initialize(record, user)
    @record = record
    @user   = user
  end

  def entries
    @entries ||= begin
      uploaded = @user.unassigned_files.blobs.group_by { self.class.normalise(it.filename.to_s) }
      claimed  = {}

      named_files.map {|named|
        blob, problem = match(named[:file], uploaded)
        entry         = Entry.new(**named, blob:, problem:)

        next entry unless blob

        if (first = claimed[blob.id])
          entry.with(blob: nil, problem: "#{entry.filename.inspect} is the same upload as #{first.where} names")
        else
          claimed[blob.id] = entry
        end
      }
    end
  end

  def unmatched = entries.reject(&:matched?)

  private

  def named_files
    LISTS.flat_map {|list|
      Array(@record[list]).each_with_index.flat_map {|object, index|
        next [] unless object.is_a?(Hash)

        Array(object['data_blocks']).flat_map { it.is_a?(Hash) ? Array(it['files']) : [] }.select { it.is_a?(Hash) }.map {|file|
          {list:, index:, object:, file:}
        }
      }
    }
  end

  def match(file, uploaded)
    name = file['filename']

    return [nil, 'names a file without a name'] unless name.is_a?(String) && name.present?

    blobs = Array(uploaded[self.class.normalise(name)])

    return [nil, "#{name.inspect} is not among the files uploaded for it (one still being checked after its upload is not, yet)"] if blobs.empty?

    method = file['checksum_method'].to_s
    hex    = file['checksum'].to_s

    return [nil, "#{name.inspect} states no MD5"] unless method.casecmp?('MD5') && hex.match?(/\A\h{32}\z/)

    md5  = Base64.strict_encode64([hex].pack('H*'))
    blob = blobs.find { it.checksum == md5 }

    blob ? [blob, nil] : [nil, "#{name.inspect} was uploaded, but its MD5 is not #{hex.downcase}"]
  end
end
