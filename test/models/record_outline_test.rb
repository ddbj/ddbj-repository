require 'test_helper'

# The layout follows the shape of the record, so the tests are about
# shapes rather than about fields — a test naming `project.title` would
# be the same standing obligation to the schema the renderer avoids.
class RecordOutlineTest < ActiveSupport::TestCase
  test 'an object becomes rows of key and value' do
    node = RecordOutline.new({'project' => {'title' => 'A study', 'hold_date' => '2026-12-01'}}).sections.sole.node

    assert_equal :fields, node.kind
    assert_equal %w[title hold_date], node.rows.map(&:first)
    assert_equal 'A study', node.rows.first.last.value
  end

  # The shape everything repeated uses: samples, entries, features, runs.
  test 'an array of like objects becomes a table' do
    samples = [{'alias' => 'S1', 'organism' => 'Homo sapiens'}, {'alias' => 'S2', 'organism' => 'Mus musculus'}]
    node    = RecordOutline.new({'samples' => samples}).sections.sole.node

    assert_equal :table,               node.kind
    assert_equal %w[alias organism],   node.columns
    assert_equal 'S1',                 node.rows.first.first.value
    assert_not   node.truncated?
  end

  # The union, so a key only some rows carry still gets a column — the
  # same rule the TSV export applies to the attribute bag.
  test 'the columns are the union across rows, in first-seen order' do
    rows = [{'alias' => 'S1', 'depth' => '10m'}, {'alias' => 'S2', 'ph' => '7.1'}]
    node = RecordOutline.new({'samples' => rows}).sections.sole.node

    assert_equal %w[alias depth ph], node.columns
    assert_nil   node.rows.last[1], 'a row without the key leaves the cell empty rather than shifting the others'
  end

  # 100K samples cannot be a page, and a screen that quietly shows twenty
  # of them reads as though there were twenty.
  test 'a collection too long to inline says how much it is not showing' do
    node = RecordOutline.new({'samples' => Array.new(1842) { {'alias' => "S#{it}"} }}).sections.sole.node

    assert node.truncated?
    assert_equal 1842, node.total
    assert_equal RecordOutline::INLINE_LIMIT, node.shown
    assert_equal 1842 - RecordOutline::INLINE_LIMIT, node.hidden
  end

  test 'a row wider than the screen keeps its remaining columns countable' do
    wide = [(1..30).to_h { ["attr#{it}", 'x'] }]
    node = RecordOutline.new({'samples' => wide}).sections.sole.node

    assert_equal 30, node.columns.size
    assert_equal RecordOutline::COLUMN_LIMIT, node.rows.first.size
  end

  # v3 gives every database the same 14 keys, so an absent one means "this
  # database has no such thing" — not an empty section to scroll past.
  test 'a key the record does not carry is not a section' do
    keys = RecordOutline.new({'project' => {'title' => 'x'}, 'samples' => nil, 'sequences' => nil}).sections.map(&:key)

    assert_equal %w[project], keys
  end

  # But one that is there and carries nothing is still there. "Present and
  # empty" and "not applicable to this database" are different facts.
  test 'a key that is present and empty is shown as empty' do
    sections = RecordOutline.new({'project' => {}, 'relations' => []}).sections

    assert_equal %w[project relations], sections.map(&:key)
    assert sections.all? { it.node.kind == :empty }
  end

  test 'repeated scalars are a list rather than a table' do
    node = RecordOutline.new({'relations' => %w[PRJDB1 PRJDB2]}).sections.sole.node

    assert_equal :list, node.kind
    assert_equal %w[PRJDB1 PRJDB2], node.rows.map(&:value)
  end

  test 'nesting recurses rather than stopping at the first level' do
    record = {'submission' => {'contact' => {'name' => 'Tanaka', 'email' => 't@example.com'}}}
    node   = RecordOutline.new(record).sections.sole.node.rows.sole.last

    assert_equal :fields,  node.kind
    assert_equal %w[name email], node.rows.map(&:first)
  end

  # A column of nothing but blanks is the same fact `hash_node` drops —
  # and here it is worse, because with a column limit in play it evicts a
  # column that has data.
  test 'a key that is nil in every row gets no column' do
    rows = [{'alias' => 'S1', 'note' => nil}, {'alias' => 'S2', 'note' => nil}]
    node = RecordOutline.new({'samples' => rows}).sections.sole.node

    assert_equal %w[alias], node.columns
  end

  test 'an array of empty objects is empty rather than a table with no columns' do
    node = RecordOutline.new({'relations' => [{}, {}]}).sections.sole.node

    assert_equal :empty, node.kind
  end

  # The 1 MB ceiling bounds bytes; this walk costs by node, and a
  # Trad-shaped record is thousands of them inside that ceiling.
  test 'a record too deep to lay out stops expanding and says so' do
    deep = {'sequences' => {'entries' => Array.new(20) {|e|
      {'alias' => "E#{e}", 'features' => Array.new(20) {|f|
        {'name' => "F#{f}", 'qualifiers' => Array.new(20) {|q| {'name' => "q#{q}", 'value' => 'v'} }}
      }}
    }}}

    outline = RecordOutline.new(deep)

    assert outline.elided?, 'the walk has to stop somewhere, and has to admit it'
  end

  test 'a record that fits is not reported as elided' do
    assert_not RecordOutline.new({'project' => {'title' => 'x'}}).elided?
  end

  # The card offers the Samples tab off the back of one section, so it has
  # to be able to ask about that one rather than about the record.
  test 'a section can be looked up by key' do
    outline = RecordOutline.new({
      'samples'   => Array.new(3) { {'alias' => 'S'} },
      'sequences' => {'entries' => [{'features' => Array.new(21) { {'name' => 'f'} }}]}
    })

    assert_not outline.section('samples').node.truncated?, 'a cut deeper in the record is not a cut here'
    assert_nil outline.section('relations'), 'a key the record does not carry has no section'
  end

  # By size, not by name. A `samples` of three rows is not worth folding
  # and a `sequences` of forty is, and neither fact is about the key.
  test 'a section is folded by how tall it draws' do
    sections = RecordOutline.new({
      'project'   => {'title' => 'A study'},
      'samples'   => Array.new(3)  {|i| {'alias' => "S#{i}"} },
      'sequences' => Array.new(40) {|i| {'alias' => "E#{i}", 'organism' => 'x'} }
    }).sections.index_by(&:key)

    assert_not sections['project'].folded?
    assert_not sections['samples'].folded?
    assert     sections['sequences'].folded?
  end

  # Height, not node count. Forty scalars draw the same twenty lines as a
  # 20x2 table and cost half as many nodes; counting nodes folded one and
  # left the other open at the same height, which has no reason a reader
  # could see.
  test 'two sections of the same height are folded alike however wide their rows' do
    outline = RecordOutline.new({
      'relations' => Array.new(40) {|i| "PRJDB#{i}" },
      'samples'   => Array.new(40) {|i| {'alias' => "S#{i}", 'organism' => 'x'} }
    }).sections.index_by(&:key)

    assert outline['relations'].folded?
    assert outline['samples'].folded?
  end

  # A row is as tall as its tallest cell, so a table of nested hashes is
  # taller than its row count suggests.
  test 'a cell holding several fields makes its row taller' do
    flat   = RecordOutline.new({'x' => Array.new(6) { {'a' => '1'} }}).sections.sole.node
    nested = RecordOutline.new({'x' => Array.new(6) { {'a' => {'b' => '1', 'c' => '2', 'd' => '3'}} }}).sections.sole.node

    assert_equal 7,  flat.height
    assert_equal 19, nested.height
  end

  # The one value given room to breathe, so the one whose length shows.
  test 'a long string is counted as the lines it wraps to' do
    short = RecordOutline.new({'project' => {'title' => 'A study'}}).sections.sole.node
    long  = RecordOutline.new({'project' => {'description' => 'x' * 500}}).sections.sole.node

    assert_equal 1, short.height
    assert_equal 5, long.height
  end

  # Closing a section must not also hide what it is: without the count the
  # reader has to open it to learn whether it was worth opening.
  test 'a node says what it holds in one line' do
    outline = RecordOutline.new({
      'samples'   => Array.new(40) {|i| {'alias' => "S#{i}", 'organism' => 'x'} },
      'relations' => %w[PRJDB1 PRJDB2],
      'project'   => {'title' => 'x', 'hold_date' => 'y'}
    }).sections.index_by(&:key)

    assert_equal '40 rows × 2 columns', outline['samples'].node.precis
    assert_equal '2 items',             outline['relations'].node.precis
    assert_equal '2 fields',            outline['project'].node.precis
  end

  # A scalar long enough to fold is the shape this class is least likely
  # to have been told about, and a fold with nothing on it says less than
  # no fold at all.
  test 'a long string says how long it is' do
    node = RecordOutline.new({'project' => 'x' * 2_500}).sections.sole.node

    assert_equal '2,500 characters', node.precis
  end

  # The record is full of one-key containers — `sequences` is
  # `{entries: [...]}` — and "1 field" is true of every one of them.
  test 'a one-key container is described by what it holds' do
    node = RecordOutline.new({
      'sequences' => {'entries' => Array.new(40) {|i| {'entry_id' => "E#{i}", 'organism' => 'x'} }}
    }).sections.sole.node

    assert_equal 'entries: 40 rows × 2 columns', node.precis
  end

  # The view asks twice — whether there is anything, then for each.
  test 'sections are built once' do
    outline = RecordOutline.new({'project' => {'title' => 'x'}})

    assert_same outline.sections, outline.sections
  end
end
