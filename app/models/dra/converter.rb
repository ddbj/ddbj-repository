# SRA XML (the documents of one DRA submission: SUBMISSION, STUDY, SAMPLE,
# EXPERIMENT, RUN, ANALYSIS, each alone or in its *_SET) to a DDBJ Record v3
# record, by the spec's table (DRA::Mapping).
#
# Nothing is converted by hand but what the table's notes say. Every element
# and attribute is looked up in the table, and one the table does not have
# raises Unmapped: the table is the spec's account of everything SRA XML can
# hold, so an item outside it is one the record would lose.
#
# A place inside a list names the element being built for the XML element
# that first needed one: its attributes, its text and its descendants write
# into the same element (`STUDY/@accession` and `STUDY/DESCRIPTOR/STUDY_TITLE`
# into one of `projects[]`), and a sibling XML element starts another. A row
# naming a list element itself (`SUBMISSION/ACTIONS/ACTION: submission.sra.
# actions[]`) starts one even if nothing is written into it.
class DRA::Converter
  SOURCE_FORMAT = 'dway_dra_xml'.freeze

  class Unmapped < StandardError; end

  # The list a document's root element is an element of, and the kind a
  # relation names it by (`source.type`).
  ROOT_LISTS = {
    'study'      => ['projects[]',    'project'],
    'sample'     => ['samples[]',     'sample'],
    'experiment' => ['experiments[]', 'experiment'],
    'run'        => ['runs[]',        'run'],
    'analysis'   => ['analyses[]',    'analysis']
  }.freeze

  # A note naming the value an element stands for: `(DDBJ_LINK なら "ddbj")`.
  NAMED_VALUE = /\A(\w+) なら "([^"]*)"\z/

  def initialize(documents:)
    @documents = documents
  end

  def call
    @record    = {'schema_version' => 'v3', 'provenance' => {'source_format' => SOURCE_FORMAT}}
    @relations = []
    @implicit  = {}.compare_by_identity

    @documents.each do |xml|
      root = Nokogiri::XML(xml, &:strict).root

      (root.name.end_with?('_SET') ? root.element_children : [root]).each do |element|
        kind = DRA::Mapping::ROOTS.fetch(element.name) { raise Unmapped, "#{element.name}: not an SRA document" }

        walk(element, kind:, path: element.name, frames: [])
      end
    end

    @relations.each { resolve_source(*it) }

    prune(@record)
  end

  private

  # One XML element: its row, its attributes, its text, its children, in a
  # frame of its own so what it starts is its descendants' alone.
  def walk(element, kind:, path:, frames:)
    frames = [*frames, {}]
    place  = place!(kind, path)

    if place == :container
      raise Unmapped, "#{path}: text in a container" if own_text(element)
    elsif place.element? && !scalar_list?(place)
      walk_segments(place.segments, place, frames, kind:, path:)
    elsif (value = element_value(element, place))
      write(place, value, frames, kind:, path:, element:)
    end

    element.attribute_nodes.each do |attribute|
      next if attribute.value.empty?

      attribute_path = "#{path}/@#{attribute.name}"

      write(place!(kind, attribute_path), attribute.value, frames, kind:, path: attribute_path, element:)
    end

    element.element_children.each do |child|
      walk(child, kind:, path: "#{path}/#{child.name}", frames:)
    end
  end

  def place!(kind, path)
    DRA::Mapping.place(kind, path) || raise(Unmapped, "#{path}: not in the SRA mapping")
  end

  def own_text(element)
    element.children.select(&:text?).map(&:text).join.presence&.then { it.strip.empty? ? nil : it }
  end

  # What an element is worth where the table puts its value: the element's
  # name, when the note says so, else its text.
  def element_value(element, place)
    case place.note
    when '要素名が値'           then element.name
    when '要素名を小文字にした値' then element.name.downcase
    when NAMED_VALUE            then element.name == $1 ? $2 : raise(Unmapped, "#{element.name}: #{place.note}")
    else                             own_text(element)
    end
  end

  def write(place, value, frames, kind:, path:, element:)
    *outer, last = place.segments
    value        = cast(place, value)
    target       = walk_segments(outer, place, frames, kind:, path:)

    # A list element the table does not name (`SAMPLE_ATTRIBUTES/TAG`,
    # `SAMPLE_ATTRIBUTES/VALUE`, … with no SAMPLE_ATTRIBUTE around each pair)
    # ends where one of its values comes round again.
    if !last.list && taken?(target, last, value) && (restart = @implicit[target])
      restart.call
      target = walk_segments(outer, place, frames, kind:, path:)
    end

    if last.list
      (target[last.name] ||= []) << value
    elsif last.key
      put(target[last.name] ||= {}, last.key, value, place)
    else
      put(target, last.name, value, place)
    end

    # `@target が無ければ submission.hold_date にも同じ値`: a HOLD for the
    # whole submission is its hold date.
    put(@record['submission'] ||= {}, 'hold_date', value, place) if place.note&.start_with?('@target が無ければ') && !element['target']
  end

  def taken?(target, last, value)
    slot = last.key ? target[last.name]&.dig(last.key) : target[last.name]

    !slot.nil? && slot != value
  end

  # Two items the table puts in one place would leave only the second.
  def put(object, key, value, place)
    raise Unmapped, "#{place}: written twice (#{object[key].inspect}, #{value.inspect})" if object.key?(key) && object[key] != value

    object[key] = value
  end

  def walk_segments(segments, place, frames, kind:, path:)
    segments.each_with_index.reduce(@record) {|object, (segment, index)|
      if segment.list
        prefix = place.segments[0..index].map(&:bare).join('.')

        frames.reverse_each.lazy.filter_map { it[prefix] }.first&.tap { annotate(it, segment) } ||
          start_element(object, segment, prefix, frames, *DRA::Mapping.anchor(kind, path, place, index), kind:)
      elsif segment.key
        (object[segment.name] ||= {})[segment.key] ||= {}
      else
        object[segment.name] ||= {}
      end
    }
  end

  # A new element of a list, held by the frame of the XML element it stands
  # for (DRA::Mapping.anchor), so that element's other items find it. One the
  # table does not name can be ended early (see #write).
  def start_element(object, segment, prefix, frames, depth, named, kind:)
    element = {}
    frame   = frames[depth - 1]

    (object[segment.name] ||= []) << element
    frame[prefix] = element
    annotate(element, segment)

    # The document's own object (a study's element of `projects[]`) is not
    # one of a run of pairs; a value coming round again there is an error.
    @implicit[element] = -> { frame.delete(prefix) } unless named || depth == 1

    # A relation's source is the document's root object, named once the whole
    # record is known (by alias, it may need an index among its namesakes).
    @relations << [element, kind, frames.first] if prefix == 'relations[]'

    element
  end

  # `identifiers[external]`, `relations[part_of sample]`: the words are the
  # element's type and, for a relation, its target's db.
  def annotate(element, segment)
    type, db = segment.annotation

    put(element, 'type', type, segment.name) if type
    put(element['target'] ||= {}, 'db', db, segment.name) if db
  end

  def resolve_source(relation, kind, root_frame)
    relation['source'] =
      if kind == 'submission'
        {'type' => 'submission', **@record.fetch('submission', {}).slice('accession', 'alias')}
      else
        list, type = ROOT_LISTS.fetch(kind)
        object     = root_frame.fetch(list)

        {'type' => type, **reference(object, list.delete_suffix('[]'))}
      end
  end

  # An object by accession, else by alias — with its position among the
  # objects sharing that alias when it does not name one alone
  # (ddbj/ddbj-record-specifications#18). Aliases are compared as the record
  # stores them, so two spelled apart only by spaces are namesakes.
  def reference(object, list)
    return {'accession' => object['accession']} if object['accession']

    klass     = DDBJRecord::Canonicalizer::PathClassifier.string_class("/#{list}/0/alias")
    stored    = ->(name) { name && DDBJRecord::Canonicalizer::StringNormalizer.normalize(name, klass) }
    namesakes = @record.fetch(list).select { stored.(it['alias']) == stored.(object['alias']) }

    {'alias' => object['alias'], 'index' => (namesakes.index { it.equal?(object) } if namesakes.size > 1)}.compact
  end

  def scalar_list?(place) = !%w[object].include?(DRA::Schema.type_at(place, element: true))

  def cast(place, value)
    case DRA::Schema.type_at(place)
    when 'integer' then Integer(value, 10)
    when 'number'  then Float(value)
    when 'boolean' then {'true' => true, 'false' => false}.fetch(value)
    else                value
    end
  rescue ArgumentError, KeyError
    raise Unmapped, "#{place}: #{value.inspect} is not a #{DRA::Schema.type_at(place)}"
  end

  # Elements of lists that nothing was written into carry nothing.
  def prune(value)
    case value
    when Hash  then value.transform_values { prune(it) }.reject { blank_container?(_2) }
    when Array then value.map { prune(it) }.reject { blank_container?(it) }
    else            value
    end
  end

  def blank_container?(value) = (value.is_a?(Hash) || value.is_a?(Array)) && value.empty?
end
