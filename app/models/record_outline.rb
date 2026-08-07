# A DDBJ Record laid out for reading, without knowing what is in it.
#
# Curators were being shown the raw JSON, which is the whole record and
# unreadable, or a curated subset, which is readable and not the whole
# record. What they asked for is the whole thing, legible — so the layout
# is decided by the shape of the data rather than by a list of fields.
#
#   Hash                        → rows of key and value
#   Array of same-shaped Hashes → a table, columns the union of their keys
#   anything else               → the value
#
# Nothing here names a field. That is the point: v3 spans every database
# in one shape (a BioProject record is one whose `samples` and
# `sequences` are simply absent), and the schema is still moving. A
# renderer that knows the fields has to be revised on every revision; one
# that reads the shape shows a new field the day it appears.
#
# The temptation to resist is per-field labels, ordering and hiding. Each
# is small and each buys a standing obligation to the schema. Key order is
# the record's own, which canonical JSON already makes deterministic.
class RecordOutline
  # Rows shown before a collection stops being inlined and becomes a
  # count. A submission can carry 100K samples and a Trad record millions
  # of entries, and those have screens of their own that paginate.
  INLINE_LIMIT = 20

  # Columns past this and the table stops being a table. The overflow is
  # named rather than dropped — a reader who cannot see that there are
  # more columns will read the ones shown as all of them.
  COLUMN_LIMIT = 12

  # Nodes built before the walk stops expanding. The 1 MB ceiling on the
  # record bounds bytes, and this walk costs by node: a Trad-shaped record
  # of 245 KB (entries × features × qualifiers, every one of them inside
  # INLINE_LIMIT) is already thousands of nodes and most of a second in
  # rendering alone. Bytes were the wrong currency for it.
  NODE_BUDGET = 3_000

  # Roughly what fits on one line of a value column at the card's width.
  # Only ever used to guess how far a long description wraps, so being a
  # little out costs nothing.
  CHARACTERS_PER_LINE = 110

  # Lines a section may draw before it starts folded. A curator reading
  # the record has business below it — the editors, the patch chain — and
  # a table of samples is a screenful to scroll past every time.
  #
  # By height rather than by name. Folding `samples` would be the shorter
  # code and would mean this class knew a field, which is the one thing it
  # is for not knowing; it would also miss a `sequences` just as tall and
  # fold a `samples` of three rows.
  #
  # Counting nodes instead was the first attempt and read as arbitrary: 40
  # scalars in `relations` draw the same twenty lines as a 20×2 table and
  # cost half as many nodes, so one folded and the other did not at the
  # same height. What costs the reader is the scrolling.
  FOLD_HEIGHT = 18

  Section = Data.define(:key, :node) do
    def folded? = node.height > FOLD_HEIGHT
  end

  # One node of the outline. `kind` is what the reader sees:
  #
  #   :fields    — key/value rows
  #   :table     — rows and columns
  #   :list      — repeated scalars
  #   :value     — a scalar
  #   :empty     — present in the record and carrying nothing
  #   :elided    — the budget ran out before this was expanded
  Node = Data.define(:kind, :rows, :columns, :total, :shown, :value) do
    def truncated? = total && shown && total > shown

    def hidden = truncated? ? total - shown : 0

    # What a folded section says about itself, so that closing it does not
    # also hide what it is. Counts, because the count is the thing a
    # reader wants before deciding to open it.
    def precis
      case kind
      when :table then "#{total} #{'row'.pluralize(total)} × #{columns.size} #{'column'.pluralize(columns.size)}"
      when :list  then "#{total} #{'item'.pluralize(total)}"
      when :fields then fields_precis
      # Long free text is the one scalar tall enough to fold, and this
      # class is written to lay out keys nobody has told it about — so the
      # shape it cannot name is the one most likely to turn up.
      when :value then "#{value.length.to_fs(:delimited)} characters" if value.is_a?(String)
      end
    end

    # Lines this node draws, near enough to decide whether it is worth
    # folding. An estimate on purpose — the exact answer is the browser's
    # and arrives too late to lay anything out with.
    def height
      case kind
      when :fields then rows.sum {|_key, child| child.height }
      when :list   then rows.sum(&:height)
      # The header, then each row as tall as its tallest cell: a cell
      # holding a two-key hash draws two lines and stretches its row.
      when :table  then 1 + rows.sum {|cells| cells.compact.map(&:height).max || 1 }
      when :value  then value.is_a?(String) ? [1, (value.length / CHARACTERS_PER_LINE.to_f).ceil].max : 1
      else 1
      end
    end

    private

    # A hash holding one key is a container rather than content, and the
    # record is full of them: `sequences` is `{entries: [...]}`, so "1
    # field" is true and tells the reader nothing they wanted to know. The
    # count worth showing is the one inside, however many layers down.
    def fields_precis
      if rows.one? && (inner = rows.sole.last.precis)
        "#{rows.sole.first}: #{inner}"
      else
        "#{rows.size} #{'field'.pluralize(rows.size)}"
      end
    end
  end

  def initialize(record)
    @record = record || {}
  end

  # How many keys v3 gives every database, read off the schema rather than
  # written down: the count is the only thing about the shape this class
  # knows, and writing it down is how "4 of 14" becomes a lie the day a
  # fifteenth key lands.
  def self.schema_key_count = DDBJRecord::V3::Root.members.size

  # The top-level keys this record carries. v3 gives every database the
  # same keys, so which ones are present is itself the answer to "does
  # this record have sequences?" — a question otherwise answered by
  # scrolling.
  def carried_keys = sections.map(&:key)

  # Whether the walk stopped short of the whole record. Said once, at the
  # top, rather than at every point it happened — the reader needs to know
  # the page is not all of it, not where each cut fell.
  def elided?
    sections

    @elided
  end

  # One top-level key, for a caller that has a reason to ask about a
  # particular one. Nothing here supplies the key: the card knows that
  # `samples` has a screen of its own, and that is a fact about the
  # workbench rather than about the record.
  def section(key) = sections.find { it.key == key }

  # Only what the record actually carries. A key whose value is nil is not
  # a section: v3 gives every database the same keys, so an absent one
  # is "this database has no such thing" rather than "this is empty".
  #
  # Memoised because the view asks twice — whether there is anything, and
  # then for each — and every ask rebuilt every node of the record.
  def sections
    @sections ||= begin
      @remaining = NODE_BUDGET
      @elided    = false

      @record.filter_map {|key, value|
        next if value.nil?

        Section.new(key:, node: node_for(value))
      }
    end
  end

  private

  def node_for(value)
    if @remaining <= 0
      @elided = true

      return Node.new(kind: :elided, rows: nil, columns: nil, total: nil, shown: nil, value: nil)
    end

    @remaining -= 1

    case value
    when Hash  then hash_node(value)
    when Array then array_node(value)
    else            Node.new(kind: :value, rows: nil, columns: nil, total: nil, shown: nil, value:)
    end
  end

  def hash_node(hash)
    return empty_node if hash.empty?

    rows = hash.filter_map {|key, value|
      next if value.nil?

      [key, node_for(value)]
    }

    return empty_node if rows.empty?

    Node.new(kind: :fields, rows:, columns: nil, total: nil, shown: nil, value: nil)
  end

  # An array of hashes is the one shape worth turning into a table, and it
  # is the shape the record uses everywhere it repeats: samples, entries,
  # features, runs. The columns are the union across the rows shown, in
  # first-seen order — the same rule SampleTSV::Exporter applies to the
  # attribute bag, so the screen and the download do not disagree about
  # what a sample has.
  def array_node(array)
    return empty_node if array.empty?

    shown = array.first(INLINE_LIMIT)

    unless shown.all?(Hash)
      return Node.new(kind: :list, rows: shown.map { node_for(it) }, columns: nil,
                      total: array.size, shown: shown.size, value: nil)
    end

    # Only keys some row actually carries a value for. `hash_node` drops a
    # nil rather than showing an empty row, and a column of nothing but
    # blanks is the same fact taking up more room — worse here, because
    # with COLUMN_LIMIT in play it evicts a column that has data.
    columns = shown.flat_map {|row| row.compact.keys }.uniq

    return empty_node if columns.empty?

    Node.new(
      kind:    :table,
      rows:    shown.map {|row| columns.first(COLUMN_LIMIT).map { row[it].nil? ? nil : node_for(row[it]) } },
      columns:,
      total:   array.size,
      shown:   shown.size,
      value:   nil
    )
  end

  def empty_node = Node.new(kind: :empty, rows: nil, columns: nil, total: nil, shown: nil, value: nil)
end
