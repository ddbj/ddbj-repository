# frozen_string_literal: true

module DDBJRecord
  # Writes a DDBJ Record JSON file with entries streamed one at a time.
  #
  # Unlike Writer, which requires a complete Root with all entries in
  # memory, StreamingWriter accepts entries via a block:
  #
  #   DDBJRecord::StreamingWriter.new(io).write(metadata, features:) do |w|
  #     parser.each_entry do |entry|
  #       w << entry.with(accession: ...)
  #     end
  #   end
  #
  # +metadata+ is a DDBJRecord::Root (with empty sequences.entries and features).
  # +features+ is a flat array of DDBJRecord::Feature.
  class StreamingWriter < Writer
    def write(metadata, features: [], &block)
      @writer.push_object

      write_root_fields(metadata)
      write_sequences(metadata.sequences.common_source, &block)
      write_value features, 'features'

      @writer.pop
      @writer.flush
    end

    def <<(entry)
      write_value entry
      self
    end

    private

    def write_root_fields(metadata)
      Root.members.each do |member|
        next if member == :sequences || member == :features

        value = metadata.public_send(member)

        write_value value, member.name if value
      end
    end

    def write_sequences(common_source)
      @writer.push_object 'sequences'

      write_value common_source, 'common_source' if common_source

      @writer.push_array 'entries'
      yield self
      @writer.pop

      @writer.pop
    end
  end
end
