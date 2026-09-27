# The spec's table of where each element and attribute of SRA XML goes in
# DDBJ Record v3 (schema/ddbj-record/mapping/sra.yml, a copy of the pinned
# spec's tests/fixtures/v3/mapping/sra.yml the Canon workflow compares).
#
# One row per item, keyed by its path from the document's root element
# (`STUDY/DESCRIPTOR/STUDY_TITLE`, `SUBMISSION/@alias`), naming a place in the
# record (`projects[].title`) or `(container)`. A place is a dotted path whose
# segments may be a list (`identifiers[external]`: the element of a list,
# with the words in the brackets being its `type` and, for a relation, its
# `target.db`) or a dict key (`properties{is_primary}`). A note in trailing
# parentheses says how a value is read when it is not the item's text.
class DRA::Mapping
  PATH = Rails.root.join('schema/ddbj-record/mapping/sra.yml')

  # The document kinds, by the root element each has.
  ROOTS = {
    'SUBMISSION' => 'submission',
    'STUDY'      => 'study',
    'SAMPLE'     => 'sample',
    'EXPERIMENT' => 'experiment',
    'RUN'        => 'run',
    'ANALYSIS'   => 'analysis'
  }.freeze

  Segment = Data.define(:name, :list, :annotation, :key) do
    # The segment as a place, without what tells elements of a list apart:
    # `identifiers[external]` and `identifiers[primary]` are one list.
    def bare = list ? "#{name}[]" : name
  end

  Place = Data.define(:segments, :note) do
    def self.parse(text)
      path, note = text.match(/\A(.*?)(?: \((.*)\))?\z/).captures

      new(
        segments: path.split('.').map {|segment|
          name, bracket = segment.match(/\A(\w+)(\[[^\]]*\]|\{[^}]*\})?\z/)&.captures || raise(ArgumentError, "cannot read #{text.inspect}")

          if bracket&.start_with?('[')
            Segment.new(name:, list: true, annotation: bracket[1..-2].split, key: nil)
          else
            Segment.new(name:, list: false, annotation: [], key: bracket && bracket[1..-2])
          end
        },
        note:
      )
    end

    # An element of a list itself, rather than a value inside one.
    def element? = segments.last.list

    def to_s = segments.map { it.list ? "#{it.name}[#{it.annotation.join(' ')}]" : [it.name, it.key && "{#{it.key}}"].join }.join('.')
  end

  CONTAINER = '(container)'

  class << self
    def rows = @rows ||= load_rows

    # The place of the item at `path` in a document of `kind`: a Place,
    # :container, or nil for an item the table does not have.
    def place(kind, path) = rows.dig(kind, path)

    # Where in a document one element of a list stands (the list ending
    # `place`'s first `index + 1` segments), for the item at `path`: how deep
    # the XML element is whose frame holds it, and whether the table names
    # that element as the list's element.
    #
    # An ancestor (or the item's own element) whose row names the list
    # element — `SAMPLE_ATTRIBUTE: samples[].attributes[]` — is that element.
    # Where none does (`STUDY` is a container, yet its items all write into
    # one of `projects[]`), it is the deepest element every such row lies
    # under, counting only rows written with the same annotation
    # (`identifiers[external]` and `identifiers[primary]` stand for different
    # XML elements).
    def anchor(kind, path, place, index)
      elements = path.sub(%r{/@[^/]+\z}, '').split('/')
      named    = named_depth(kind, elements, place.segments[0..index])

      named ? [named, true] : [implicit_depth(kind, place.segments[0..index]), false]
    end

    private

    def named_depth(kind, elements, segments)
      elements.size.downto(1).find {|depth|
        row = place(kind, elements.first(depth).join('/'))

        row.is_a?(Place) && row.element? && row.segments.map(&:bare) == segments.map(&:bare)
      }
    end

    def implicit_depth(kind, segments)
      (@implicit ||= {})[[kind, segments]] ||= begin
        paths = rows.fetch(kind).filter_map {|path, other|
          next unless other.is_a?(Place) && other.segments[0..(segments.size - 1)] == segments

          elements = path.sub(%r{/@[^/]+\z}, '').split('/')
          elements unless named_depth(kind, elements, segments)
        }

        paths.reduce {|common, path| common.zip(path).take_while { _1 == _2 }.map(&:first) }.size
      end
    end

    def load_rows
      YAML.safe_load_file(PATH).to_h {|kind, items|
        [kind, items.to_h {|path, place| [path, place == CONTAINER ? :container : Place.parse(place)] }]
      }
    end
  end
end
