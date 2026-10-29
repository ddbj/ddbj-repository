require 'test_helper'

# script/dra-mover, which carries out what DRA::PublicationRequests asks
# for, as the account that owns the public trees.
class DRAMoverTest < ActiveSupport::TestCase
  MOVER = Rails.root.join('script/dra-mover').to_s

  Move = DRA::PublicationRequests::Move

  setup do
    @root     = Pathname.new(Dir.mktmpdir)
    @public   = @root.join('public').tap(&:mkpath)
    @staging  = @root.join('staging').tap(&:mkpath)
    @requests = DRA::PublicationRequests.new(@root.join('requests').tap(&:mkpath))
  end

  teardown do
    @root.rmtree
  end

  def put(path, body = 'reads') = path.tap { it.dirname.mkpath }.tap { it.write(body) }

  def mover(*args)
    Open3.capture2e('python3', MOVER, '--requests', @requests.root.to_s, '--tree', "dra=#{@public}:#{@staging}", *args)
  end

  def move!
    output, status = mover

    assert status.success?, output

    output
  end

  def ask(accession, *moves, action: :publish, at: Time.current) = @requests.submit(accession, action, moves.map { Move.new(op: it[0], tree: :dra, path: it[1]) }, requested_at: at)

  def collected = [].tap {|requests| @requests.collect { requests << it } }

  FASTQ = 'fastq/DRA000/DRA000001/DRX000001/DRR000001_1.fastq.bz2'

  test 'publishes as D-way did, and takes out the directories it leaves empty, up to the shared ones' do
    put @staging.join(FASTQ)

    ask 'DRA000001', [:publish, FASTQ]
    move!

    assert_equal 'reads', @public.join(FASTQ).read
    assert_equal '100644', format('%o', @public.join(FASTQ).stat.mode)
    assert_equal '40755', format('%o', @public.join(FASTQ).dirname.stat.mode)

    assert_not @staging.join('fastq/DRA000/DRA000001').exist?
    assert @staging.join('fastq/DRA000').exist?

    assert_equal [[:publish, nil]], collected.map { [it.action, it.error] }
  end

  # The repository goes on writing beside what is moved back.
  test 'what is taken out goes back into group-writable directories' do
    put @public.join(FASTQ)

    ask 'DRA000001', [:withdraw, FASTQ], action: :withdraw
    move!

    assert @staging.join(FASTQ).exist?
    assert_equal '42775', format('%o', @staging.join(FASTQ).dirname.stat.mode)
  end

  # Stopped part way, a request is carried out again from the start.
  test 'a move already made is done' do
    put @public.join(FASTQ)

    ask 'DRA000001', [:publish, FASTQ]
    move!

    assert_nil collected.sole.error
  end

  test 'one that fails says why, and the others are carried out all the same' do
    put @staging.join(FASTQ)

    ask 'DRA000002', [:publish, 'fastq/DRA000/DRA000002/DRA000002.run.xml'], at: 1.minute.ago
    ask 'DRA000001', [:publish, FASTQ]
    move!

    assert @public.join(FASTQ).exist?
    assert_equal [['DRA000002', 'in neither tree: dra/fastq/DRA000/DRA000002/DRA000002.run.xml'], ['DRA000001', nil]], collected.map { [it.accession, it.error] }
  end

  test 'refuses a path that is not plain, a tree it was not told of, and an op it does not know' do
    put @root.join('secret')

    ask 'DRA000001', [:publish, '../secret']
    ask 'DRA000002', [:publish, '/etc/passwd']
    ask 'DRA000003', [:publish, 'fastq//x']
    @requests.submit 'DRA000004', :publish, [Move.new(op: :publish, tree: :sra, path: 'x')], requested_at: Time.current
    ask 'DRA000005', [:delete, FASTQ]
    move!

    assert_equal(
      ["not a plain path: '../secret'", "not a relative path: '/etc/passwd'", "not a plain path: 'fastq//x'", "no tree 'sra'", "no op 'delete'"],
      collected.sort_by(&:accession).map(&:error)
    )
    assert @root.join('secret').exist?
  end

  # The public tree is shared, and a link in it leads anywhere.
  test 'refuses anything reached through a link, on either side' do
    elsewhere = @root.join('elsewhere').tap(&:mkpath)
    put elsewhere.join('DRR000001_1.fastq.bz2')

    @public.join('fastq').make_symlink(elsewhere)
    put @staging.join(FASTQ)

    ask 'DRA000001', [:withdraw, 'fastq/DRR000001_1.fastq.bz2'], action: :withdraw
    ask 'DRA000002', [:publish, FASTQ]
    move!

    assert_equal ["reached through a link: #{@public.join('fastq')}"] * 2, collected.map(&:error)
    assert elsewhere.join('DRR000001_1.fastq.bz2').exist?
    assert @staging.join(FASTQ).exist?
  end

  test 'refuses trees on two filesystems, whose moves would be copies' do
    output, status = Open3.capture2e('python3', MOVER, '--requests', @requests.root.to_s, '--tree', "dra=#{@public}:/proc")

    assert_not status.success?
    assert_match 'different filesystems', output
  end

  test 'one run at a time' do
    File.open(@requests.root.join('.lock'), 'a') do |lock|
      lock.flock File::LOCK_EX

      ask 'DRA000001', [:publish, FASTQ]

      assert_match 'another run holds the lock', move!
    end

    assert_equal 1, @requests.root.glob('*.json').size
  end
end
