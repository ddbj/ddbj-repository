# The object a relation's source or target names within the record, read
# the way they are written (ddbj/ddbj-record-specifications#18;
# DRA::Converter#reference writes them): by accession where one is given;
# otherwise by alias — compared as the record stores it, so two spelled
# apart only by spaces are namesakes, and objects with no alias are
# namesakes of each other — and, among namesakes, by its position.
#
# A source names its alias as `alias`; a target names it as `id`.
module DDBJRecord::References
  module_function

  # nil where it names nothing, or names namesakes without saying which.
  def resolve(record, list, accession: nil, name: nil, index: nil)
    objects = Array(record[list]).select { it.is_a?(Hash) }

    return objects.find { it['accession'] == accession } if accession.present?

    key       = normalise(list, name)
    namesakes = objects.select { normalise(list, it['alias']) == key }

    return namesakes.first if namesakes.one? && index.nil?
    return nil unless index.is_a?(Integer)

    namesakes[index]
  end

  def source(record, list, source) = resolve(record, list, accession: source['accession'], name: source['alias'], index: source['index'])

  def target(record, list, target) = resolve(record, list, accession: target['accession'], name: target['id'], index: target['index'])

  def normalise(list, name)
    DDBJRecord::Canonicalizer::StringNormalizer.normalize(name.to_s, DDBJRecord::Canonicalizer::PathClassifier.string_class("/#{list}/0/alias"))
  rescue DDBJRecord::Canonicalizer::Error
    name.to_s
  end
end
