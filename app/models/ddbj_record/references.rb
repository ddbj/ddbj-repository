# The object a relation's source or target names within the record, read
# the way they are written (ddbj/ddbj-record-specifications#18;
# DRA::Converter#reference writes them): by accession where one is given;
# otherwise by alias — compared as the record stores it, so two spelled
# apart only by spaces are namesakes, and objects with no alias are
# namesakes of each other — and, among namesakes, by its position.
#
# A source names its alias as `alias`; a target names it as `id`.
module DDBJRecord::References
  # A record's objects indexed once, for resolving many references in it:
  # resolving one by one reads the whole list each time, which a document
  # of a thousand runs each naming its experiment does a million times.
  class Index
    def initialize(record)
      @record = record
    end

    # nil where it names nothing, or names namesakes without saying which.
    def resolve(list, accession: nil, name: nil, index: nil)
      return by_accession(list)[accession] if accession.present?

      namesakes = by_name(list).fetch(DDBJRecord::References.normalise(list, name), [])

      return namesakes.first if namesakes.one? && index.nil?
      return nil unless index.is_a?(Integer)

      namesakes[index]
    end

    def source(list, source) = resolve(list, accession: source['accession'], name: source['alias'], index: source['index'])

    def target(list, target) = resolve(list, accession: target['accession'], name: target['id'], index: target['index'])

    private

    def objects(list) = (@objects ||= {})[list] ||= Array(@record[list]).select { it.is_a?(Hash) }

    def by_accession(list) = (@by_accession ||= {})[list] ||= objects(list).reverse.index_by { it['accession'] }.except(nil)

    # Only where an alias is looked up: normalising every alias costs more
    # than a lookup by accession.
    def by_name(list) = (@by_name ||= {})[list] ||= objects(list).group_by { DDBJRecord::References.normalise(list, it['alias']) }
  end

  module_function

  def resolve(record, list, ...) = Index.new(record).resolve(list, ...)

  def source(record, list, source) = Index.new(record).source(list, source)

  def target(record, list, target) = Index.new(record).target(list, target)

  def normalise(list, name)
    DDBJRecord::Canonicalizer::StringNormalizer.normalize(name.to_s, DDBJRecord::Canonicalizer::PathClassifier.string_class("/#{list}/0/alias"))
  rescue DDBJRecord::Canonicalizer::Error
    name.to_s
  end
end
