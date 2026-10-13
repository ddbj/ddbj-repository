# SRA XML as the XSD D-way publishes it in (1.6.1, schema/sra/1.6.1, the
# version its JAXB beans are generated from): which elements and attributes
# a document of each kind may hold, and in what order. DRA::XMLRenderer
# writes by it, since the mapping table (DRA::Mapping) is in no order and
# holds every version's items, and what is not in this version would not
# validate.
#
# Read from the schema rather than written down: the SRA XSDs use only
# named and inline types, sequences, choices and `all`, attribute groups
# and simple content, so the tree is what those spell out.
module DRA::XSD
  DIR = Rails.root.join('schema/sra/1.6.1')

  FILES = {
    'submission' => 'SRA.submission.xsd',
    'study'      => 'SRA.study.xsd',
    'sample'     => 'SRA.sample.xsd',
    'experiment' => 'SRA.experiment.xsd',
    'run'        => 'SRA.run.xsd',
    'analysis'   => 'SRA.analysis.xsd'
  }.freeze

  XS = {'xs' => 'http://www.w3.org/2001/XMLSchema'}.freeze

  # One element: the type of its text (nil for none), its attributes with
  # theirs, and its children, in the schema's order; whether its parent
  # must hold it (not optional, and not one of a choice), and the branch of
  # a choice it is in, if it is — the choice and the branch, since only one
  # branch's elements may be written. Children are read when first asked
  # for, so a type is spelled out only as deep as a document goes.
  Element = Struct.new(:name, :type, :attributes, :required, :choice, :content) do
    def children = @children ||= content.call

    def text? = !type.nil?

    def required? = required
  end

  module_function

  # The root element of a document of `kind` ('experiment' → EXPERIMENT).
  def root(kind) = (@roots ||= {})[kind] ||= element(global(kind.upcase), required: true, choice: nil)

  # The XSD a document of `kind` is valid by, its includes resolved.
  def schema(kind)
    path = DIR.join(FILES.fetch(kind))

    (@schemas ||= {})[kind] ||= Nokogiri::XML::Schema.from_document(Nokogiri::XML(path.read, path.to_s))
  end

  # A type of its own, or a named complex type; anything else (`xs:string`,
  # a named simple type) is text.
  def element(definition, required:, choice:)
    type    = definition['type']
    complex = definition.at_xpath('xs:complexType', XS) || (top_level('complexType', type) if type && !type.start_with?('xs:'))
    simple  = complex&.at_xpath('xs:simpleContent/xs:extension', XS)

    return Element.new(definition['name'], type || 'xs:string', {}, required, choice, -> { [] }) unless complex

    Element.new(definition['name'], simple&.[]('base'), attributes_of(simple || complex), required, choice, -> {
      simple ? [] : elements_of(complex).map { element(_1, required: _2, choice: _3) }
    })
  end

  def documents = @documents ||= DIR.glob('SRA.*.xsd').map { Nokogiri::XML(it.read) }

  def global(name) = top_level('element', name) || raise(KeyError, "no element #{name} in the SRA XSD")

  def top_level(tag, name)
    documents.lazy.filter_map { it.at_xpath("/xs:schema/xs:#{tag}[@name='#{name}']", XS) }.first
  end

  def attributes_of(node)
    node.xpath('xs:attribute | xs:attributeGroup', XS).each_with_object({}) {|item, attributes|
      if item.name == 'attribute'
        attributes[item['name']] = item['type'] || 'xs:string'
      else
        attributes.merge! attributes_of(top_level('attributeGroup', item['ref']))
      end
    }
  end

  # The child elements, in order, through sequences, choices and `all`,
  # each with whether it is required and the branch of a choice it is in.
  def elements_of(node, chosen: false, choice: nil)
    node.element_children.flat_map {|child|
      case child.name
      when 'element'
        [[child, !chosen && child['minOccurs'] != '0', choice]]
      when 'sequence', 'all'
        elements_of(child, chosen: chosen || child['minOccurs'] == '0', choice:)
      when 'choice'
        child.element_children.each_with_index.flat_map {|branch, index|
          branch.name == 'element' ? [[branch, false, [child.path, index]]] : elements_of(branch, chosen: true, choice: [child.path, index])
        }
      else
        []
      end
    }
  end

  private_class_method :element, :documents, :global, :top_level, :attributes_of, :elements_of
end
