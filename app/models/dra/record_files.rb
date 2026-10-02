# The files a DRA record's runs and analyses name, each matched to the file
# its submitter uploaded for it: by name, among the uploader's unassigned
# files, and then by MD5, which the record states and the store computed
# when the upload was verified — so matching reads nothing.
#
# The files are uploaded before the record is sent (CLAUDE.md, "Data file
# uploads"), and wait among the uploader's unassigned files until a
# submission is assigned them. Both checking a record (RecordIntake) and
# applying it ask this, so the two cannot disagree on which file is whose.
class DRA::RecordFiles
  # One FILE of the record: where it is (`runs[0]`), what it says, and the
  # upload it names — or why there is none.
  Entry = Data.define(:list, :index, :object, :file, :blob, :problem) do
    def where    = "#{list}[#{index}]"
    def filename = file['filename']
    def matched? = !blob.nil?
  end

  LISTS = %w[runs analyses].freeze

  def initialize(record, user)
    @record = record
    @user   = user
  end

  def entries
    @entries ||= begin
      named    = named_files
      uploaded = @user.unassigned_files.blobs.where(filename: named.map { it[:file]['filename'] }.compact.uniq).group_by { it.filename.to_s }

      named.map {|n|
        blob, problem = match(n[:file], Array(uploaded[n[:file]['filename'].to_s]))

        Entry.new(**n, blob:, problem:)
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

  def match(file, blobs)
    name = file['filename'].to_s

    return [nil, 'names no file'] if name.blank?
    return [nil, "#{name} has not been uploaded"] if blobs.empty?

    method = file['checksum_method'].to_s
    hex    = file['checksum'].to_s

    return [nil, "#{name} states no MD5"] unless method.casecmp?('MD5') && hex.match?(/\A\h{32}\z/)

    md5 = [hex].pack('H*').then { Base64.strict_encode64(it) }

    blob = blobs.find { it.checksum == md5 }

    blob ? [blob, nil] : [nil, "#{name} was uploaded, but its MD5 is not #{hex.downcase}"]
  end
end
