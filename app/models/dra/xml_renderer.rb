# A DDBJ Record v3 record to SRA XML: DRA::Converter the other way, by the
# same table (DRA::Mapping), in the version D-way publishes (DRA::XSD).
#
# The XSD says what is written and in what order; the table says where in
# the record each item's value is. An element of a list (an experiment, an
# attribute, a relation) is written once for each element of the list the
# XML element stands for — the one the converter would have built for it
# (DRA::Mapping.anchor) — and a relation only by the document whose object
# is its source.
#
# What the version cannot hold is not written, as D-way's JAXB beans did
# not: items of older versions, and those in no XSD (`legacy`). An element
# of a list is written by the XML element written with its kind (`fits?`):
# an xref by XREF_LINK, a URL by URL_LINK.
class DRA::XMLRenderer
  KINDS = %w[submission study sample experiment run analysis].freeze

  def initialize(record)
    @record    = record
    @relations = relations_by_source(record)
  end

  # Each kind the record has objects of, with its document: SUBMISSION for
  # the submission, a *_SET of the others.
  def call
    KINDS.each_with_object({}) {|kind, documents|
      document = document(kind)

      documents[kind] = document if document
    }
  end

  private

  def document(kind)
    @kind     = kind
    @document = Nokogiri::XML::Document.new
    @used     = Set.new.compare_by_identity
    root      = DRA::XSD.root(kind)

    if kind == 'submission'
      @document.root = render(root, root.name, {}, source: :submission) or return
    else
      list    = DRA::Converter::ROOT_LISTS.fetch(kind).first
      objects = Array(@record[list.delete_suffix('[]')]).select { it.is_a?(Hash) }

      return if objects.empty?

      @document.root = @document.create_element("#{root.name}_SET")

      objects.each do |object|
        @document.root << render(root, root.name, {list => object}, source: object)
      end
    end

    @document
  end

  # The element at `path`, given the elements of lists it is inside of
  # (`binding`, by their bare place: `experiments[]`); nil if it would hold
  # nothing.
  def render(element, path, binding, source:)
    place = DRA::Mapping.place(@kind, path)
    named = place.is_a?(DRA::Mapping::Place) && !place.element? && place.value_of(element.name)

    return if named && value(place, binding) != named

    node = @document.create_element(element.name)

    element.attributes.each do |attribute, type|
      attribute_place = DRA::Mapping.place(@kind, "#{path}/@#{attribute}")
      text            = text(attribute_place, value(attribute_place, binding), type) if attribute_place.is_a?(DRA::Mapping::Place)

      node[attribute] = text if text
    end

    if element.text? && place.is_a?(DRA::Mapping::Place) && !named
      text = text(place, value(place, binding), element.type)

      node.content = text if text
    end

    children = one_branch(element.children.flat_map { render_child(it, "#{path}/#{it.name}", binding, source:) })

    return unless named || node.attribute_nodes.any? || node.children.any? || children.any? { _2 }

    children.each do |child, rendered|
      node << (rendered || skeleton(child))
    end

    node
  end

  # The child's elements, each as [the child, the element] — or, where it
  # has nothing to say and the version may want it written anyway (see
  # #skeleton), [the child, nil].
  def render_child(child, path, binding, source:)
    prefix = stands_for(path)

    # An element inside the one standing for the same list element
    # (STUDY_LINK, then the XREF_LINK in it) is that element again, of the
    # kind the item is.
    rendered =
      if prefix && binding.key?(bare(prefix))
        [(render(child, path, binding, source:) if fits?(path, prefix, binding[bare(prefix)]))].compact
      elsif prefix
        elements_of(prefix, binding, source).filter_map {|item|
          next if @used.include?(item) || !fits?(path, prefix, item)

          @used << item

          render(child, path, binding.merge(bare(prefix) => item), source:)
        }
      else
        [render(child, path, binding, source:)].compact
      end

    return rendered.map { [child, it] } if rendered.any?

    child.required? ? [[child, nil]] : []
  end

  # Of the branches of a choice, the first that holds something: a record
  # may have values for two (a SAMPLE_DESCRIPTOR naming its sample and
  # describing a pool), and the version takes one. Where none does, none
  # is written — not even where the version requires one: which it would
  # be (a single library, a standard assembly) is the record's to say, and
  # a document missing it is refused rather than made to say it.
  def one_branch(children)
    taken = children.each_with_object({}) {|(child, rendered), taken|
      choice, branch = child.choice

      taken[choice] ||= branch if choice && rendered
    }

    children.select {|child, rendered|
      choice, branch = child.choice

      choice.nil? || (rendered && taken[choice] == branch)
    }
  end

  # An element the version requires where the record has nothing for it:
  # the element, holding what the version requires of it in turn — never a
  # branch of a choice (see #one_branch). The converter reads an element
  # saying nothing as none (D-way's documents have
  # `<STEP_INDEX></STEP_INDEX>` in a PIPE_SECTION), so writing it back takes
  # this. Only beside what its parent does hold: an element holding nothing
  # else is not written.
  def skeleton(element)
    @document.create_element(element.name).tap {|node|
      element.children.select(&:required?).each do |child|
        node << skeleton(child)
      end
    }
  end

  # The value at `place`: through the elements `binding` holds for its
  # lists, nil where it is inside a list element not bound.
  def value(place, binding)
    place.segments.each_with_index.reduce(@record) {|object, (segment, index)|
      if segment.list
        binding[bare(place.segments[0..index])]
      elsif !object.is_a?(Hash)
        nil
      elsif segment.key
        object[segment.name].then { it[segment.key] if it.is_a?(Hash) }
      else
        object[segment.name]
      end
    }
  end

  # As the converter read it: true and false, numbers in decimal notation,
  # and the record's name of an object type as SRA's (`project` → STUDY).
  # A date where the version wants a moment is the start of that day in
  # Tokyo, as D-way writes its dates (`2011-04-07T00:00:00+09:00`).
  def text(place, value, type)
    return if value.nil? || value.is_a?(Hash) || value.is_a?(Array)
    return kind_element(value) if place.note == DRA::Mapping::KIND_NAME

    case value
    when Float      then value.finite? && value == value.round ? value.round.to_s : value.to_s
    when BigDecimal then value.frac.zero? ? value.to_i.to_s : value.to_s('F')
    when DATE_ONLY  then type == 'xs:dateTime' ? "#{value}T00:00:00+09:00" : value
    else                 value.to_s
    end
  end

  DATE_ONLY = /\A\d{4}-\d{2}-\d{2}\z/

  def kind_element(name)
    kind = DRA::Converter::ROOT_LISTS.find { _2[1] == name }&.first || name

    DRA::Mapping::ROOTS.key(kind) || name
  end

  # The list (as its place's segments) the XML element at `path` stands an
  # element of, if any — the document's own object aside, which #document
  # binds.
  def stands_for(path) = standing[path]

  def standing
    (@standing ||= {})[@kind] ||= DRA::Mapping.rows.fetch(@kind).each_with_object({}) {|(path, place), standing|
      # An older version's rows say nothing of this one's elements: its
      # SAMPLE_ATTRIBUTES held TAG and VALUE pairs without a SAMPLE_ATTRIBUTE.
      next unless place.is_a?(DRA::Mapping::Place) && in_version?(path)

      place.segments.each_with_index do |segment, index|
        next unless segment.list

        depth, = DRA::Mapping.anchor(@kind, path, place, index)

        next if depth == 1

        standing[elements(path).first(depth).join('/')] ||= place.segments[0..index]
      end
    }
  end

  def elements(path) = path.sub(%r{/@[^/]+\z}, '').split('/')

  def bare(segments) = segments.map(&:bare).join('.')

  # The elements of the list `prefix` ends with, inside what is bound. The
  # record's relations are listed with the documents of their sources, so
  # only those whose source is this document's object.
  def elements_of(prefix, binding, source)
    *outer, last = prefix

    return @relations.fetch(source, []) if outer.empty? && last.name == 'relations'

    holder = outer.empty? ? @record : value(DRA::Mapping::Place.new(segments: outer, note: nil), binding)

    (holder[last.name] if holder.is_a?(Hash)).then { it.is_a?(Array) ? it : [] }
  end

  # The record's relations by the object each is from (:submission for the
  # submission), resolved once: a run's document of a thousand runs each
  # naming its experiment would otherwise resolve a million.
  def relations_by_source(record)
    references = DDBJRecord::References::Index.new(record)
    lists      = DRA::Converter::ROOT_LISTS.values.to_h { [_2, _1.delete_suffix('[]')] }

    Array(record['relations']).each_with_object({}.compare_by_identity) {|relation, by_source|
      source = relation['source'] if relation.is_a?(Hash)

      next unless source.is_a?(Hash)

      object =
        if source['type'] == 'submission'
          :submission
        elsif lists.key?(source['type'])
          references.source(lists[source['type']], source)
        end

      (by_source[object] ||= []) << relation if object
    }
  end

  # Whether the XML element at `path` is where `item` goes: one written
  # with the item's kind (`relations[xref]` for an xref, `[reference]` for a
  # URL), able to hold something of it. What the version has no place for
  # is left out of it, as D-way's beans left it (an EXTERNAL_ID's label).
  # What an item names its source by is the document's, and an index among
  # namesakes is no XML's.
  def fits?(path, prefix, item)
    rows = coverage(path, prefix).select {|annotation, _| annotation_matches?(annotation, item) }

    return false if rows.empty?

    covered = rows.flat_map { _2 }.to_set

    leaves(item, top: prefix.first.name == 'relations').any? { covered.include?(it) }
  end

  def annotation_matches?(annotation, item)
    type, db = annotation

    return true if type.nil?
    return item == type if !item.is_a?(Hash)

    item['type'] == type && (db.nil? || item.dig('target', 'db') == db)
  end

  # The rows under the XML element at `path` writing into an element of
  # `prefix`'s list, as [the list's annotation, the places they write
  # relative to it]. An annotation is a value written too: `relations[xref]`
  # writes `type`.
  def coverage(path, prefix)
    (@coverage ||= {})[[@kind, path, bare(prefix)]] ||= DRA::Mapping.rows.fetch(@kind).filter_map {|row_path, place|
      next unless place.is_a?(DRA::Mapping::Place) && (row_path == path || row_path.start_with?("#{path}/")) && in_version?(row_path)
      next unless place.segments.size >= prefix.size && bare(place.segments.first(prefix.size)) == bare(prefix)

      relative   = place.segments.drop(prefix.size)
      annotation = place.segments[prefix.size - 1].annotation

      [annotation, [*annotated(annotation, ''), *relative_leaves(relative)]]
    }
  end

  # The places of `segments` (below the list element) as #leaves names
  # them, with what the annotations of lists inside it write.
  def relative_leaves(segments)
    nested = segments.each_index.select { segments[it].list && segments[it].annotation.any? }

    [leaf(segments), *nested.flat_map { annotated(segments[it].annotation, "#{leaf(segments.first(it + 1))}.") }]
  end

  def leaf(segments)
    segments.map {|segment|
      [segment.name, (".#{segment.key}" if segment.key), ('[]' if segment.list)].join
    }.join('.')
  end

  def annotated(annotation, prefix)
    type, db = annotation

    [("#{prefix}type" if type), ("#{prefix}target.db" if db)].compact
  end

  # The item's values, by where they are relative to it (`target.db`,
  # `properties.is_primary`, `identifiers[].value`).
  def leaves(item, top:, prefix: '')
    case item
    when Hash
      item.flat_map {|key, value|
        next [] if top && prefix.empty? && key == 'source'
        next [] if key == 'index'

        leaves(value, top:, prefix: [prefix.presence, key].compact.join('.'))
      }
    when Array
      item.flat_map { leaves(it, top:, prefix: "#{prefix}[]") }
    else
      [prefix]
    end
  end

  def in_version?(path) = version_paths.include?(path)

  def version_paths
    (@version_paths ||= {})[@kind] ||= Set.new.tap {|paths|
      walk = ->(element, path) {
        paths << path
        element.attributes.each_key { paths << "#{path}/@#{it}" }
        element.children.each { walk.(it, "#{path}/#{it.name}") }
      }

      walk.(DRA::XSD.root(@kind), DRA::XSD.root(@kind).name)
    }
  end
end
