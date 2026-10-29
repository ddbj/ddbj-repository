require 'test_helper'

# script/dra-mover, which carries out what DRA::PublicationRequests asks
# for, as the account that owns the public tree. One account runs both
# sides here, so what rests on two (who may chmod what) is not tried.
class DRAMoverTest < ActiveSupport::TestCase
  MOVER = Rails.root.join('script/dra-mover').to_s

  Move = DRA::PublicationRequests::Move

  FASTQ = 'fastq/DRA000/DRA000001/DRX000001/DRR000001_1.fastq.bz2'
  SRA   = 'sra/ByExp/sra/DRX/DRX000/DRX000001/DRR000001/DRR000001.sra'

  setup do
    @root     = Pathname.new(Dir.mktmpdir)
    @public   = @root.join('public').tap(&:mkpath)
    @private  = @root.join('private').tap(&:mkpath)
    @requests = DRA::PublicationRequests.new(@root.join('requests').tap(&:mkpath))
    @hold     = @root.join('hold').tap(&:mkpath).tap { it.chmod(0o700) }
  end

  teardown do
    @root.rmtree
  end

  def put(path, body = 'reads') = path.tap { it.dirname.mkpath }.tap { it.write(body) }.tap { it.chmod(0o644) }

  def mover(*args, public: @public, private: @private)
    Open3.capture2e('python3', MOVER, '--requests', @requests.root.to_s, '--lock', @root.join('mover.lock').to_s, '--tree', "dra=#{public}:#{private}:#{@hold}", *args)
  end

  def move!
    output, status = mover

    assert status.success?, output

    output
  end

  def ask(accession, *moves, action: :publish, at: Time.current) = @requests.submit(accession, action, moves.map { Move.new(op: it[0], tree: :dra, path: it[1]) }, requested_at: at)

  def settled = [].tap {|requests| @requests.each_settled { requests << it } }

  test 'publishes as D-way did, and takes out the directories it leaves empty, up to the shared ones' do
    put @private.join(FASTQ)
    put @private.join(SRA)

    ask 'DRA000001', [:publish, FASTQ], [:publish, SRA]
    move!

    assert_equal 'reads', @public.join(FASTQ).read
    assert_equal '100644', format('%o', @public.join(FASTQ).stat.mode)
    assert_equal '40755', format('%o', @public.join(FASTQ).dirname.stat.mode)

    assert_not @private.join('fastq/DRA000/DRA000001').exist?
    assert @private.join('fastq/DRA000').exist?
    assert_not @private.join('sra/ByExp/sra/DRX/DRX000/DRX000001').exist?
    assert @private.join('sra/ByExp/sra/DRX/DRX000').exist?

    assert_equal [[:publish, nil]], settled.map { [it.action, it.error] }
    assert_empty @hold.children, 'gone through'
  end

  # The repository goes on writing beside what is moved back.
  test 'what is taken out goes back into group-writable directories' do
    put @public.join(FASTQ)

    ask 'DRA000001', [:withdraw, FASTQ], action: :withdraw
    move!

    assert @private.join(FASTQ).exist?
    assert_equal '42775', format('%o', @private.join(FASTQ).dirname.stat.mode)
    assert_not @public.join('fastq/DRA000/DRA000001').exist?
  end

  # Stopped part way, a request is carried out again from the start.
  test 'a move already made is done' do
    put @public.join(FASTQ)

    ask 'DRA000001', [:publish, FASTQ]
    move!

    assert_nil settled.sole.error
  end

  test 'one that fails says why, and the others are carried out all the same' do
    put @private.join(FASTQ)

    ask 'DRA000002', [:publish, 'fastq/DRA000/DRA000002/DRA000002.run.xml'], at: 1.minute.ago
    ask 'DRA000001', [:publish, FASTQ]
    move!

    assert @public.join(FASTQ).exist?
    assert_equal [['DRA000002', 'in neither tree: dra/fastq/DRA000/DRA000002/DRA000002.run.xml'], ['DRA000001', nil]], settled.map { [it.accession, it.error] }
  end

  test "refuses a path that is not plain, not the submission's, of a tree it was not told of, or an op it does not know" do
    put @root.join('secret')

    ask 'DRA000001', [:publish, '../secret']
    ask 'DRA000002', [:publish, '/etc/passwd']
    ask 'DRA000003', [:publish, 'fastq//x']
    ask 'DRA000004', [:publish, 'fastq/DRA000/DRA000001/DRX000001/a.bz2']
    ask 'DRA000005', [:publish, 'sra/ByExp/sra/SRX/SRX000/SRX000001/SRR000001/SRR000001.sra']
    @requests.submit 'DRA000006', :publish, [Move.new(op: :publish, tree: :sra, path: 'x')], requested_at: Time.current
    ask 'DRA000007', [:delete, 'fastq/DRA000/DRA000007/DRX000001/a.bz2']
    move!

    assert_equal(
      [
        "not a plain path: '../secret'",
        "not a plain path: '/etc/passwd'",
        "not a plain path: 'fastq//x'",
        'not a path of DRA000004: fastq/DRA000/DRA000001/DRX000001/a.bz2',
        'not a path of DRA000005: sra/ByExp/sra/SRX/SRX000/SRX000001/SRR000001/SRR000001.sra',
        "no tree 'sra'",
        "no op 'delete'"
      ],
      settled.sort_by(&:accession).map(&:error)
    )
    assert @root.join('secret').exist?
  end

  # The mirror's are beside the submission's own.
  test 'replaces nothing public but the documents' do
    put @public.join(FASTQ), 'theirs'
    put @private.join(FASTQ), 'ours'
    put @public.join('fastq/DRA000/DRA000001/DRA000001.run.xml'), 'old'
    put @private.join('fastq/DRA000/DRA000001/DRA000001.run.xml'), 'new'

    ask 'DRA000001', [:publish, 'fastq/DRA000/DRA000001/DRA000001.run.xml'], [:publish, FASTQ]
    move!

    assert_equal "already public: #{FASTQ}", settled.sole.error
    assert_equal 'theirs', @public.join(FASTQ).read
    assert_equal 'new', @public.join('fastq/DRA000/DRA000001/DRA000001.run.xml').read
  end

  # The public tree is shared, and a link in it leads anywhere.
  test 'refuses anything reached through a link, on either side' do
    elsewhere = @root.join('elsewhere').tap(&:mkpath)
    put elsewhere.join('DRA000/DRA000001/DRX000001/DRR000001_1.fastq.bz2')

    @public.join('fastq').make_symlink(elsewhere)

    put @root.join('secret')
    @private.join('fastq/DRA000/DRA000002/DRX000002').tap(&:mkpath).join('a.bz2').make_symlink(@root.join('secret'))

    ask 'DRA000001', [:withdraw, FASTQ], action: :withdraw
    ask 'DRA000002', [:publish, 'fastq/DRA000/DRA000002/DRX000002/a.bz2']
    move!

    assert_equal ['not a directory, or a link: fastq', 'not a file: fastq/DRA000/DRA000002/DRX000002/a.bz2'], settled.map(&:error)
    assert elsewhere.join('DRA000/DRA000001/DRX000001/DRR000001_1.fastq.bz2').exist?
  end

  test 'takes public only a file writable by its owner alone, and not linked elsewhere' do
    put(@private.join(FASTQ)).chmod(0o664)
    put @private.join('fastq/DRA000/DRA000002/DRX000002/a.bz2')
    FileUtils.ln @private.join('fastq/DRA000/DRA000002/DRX000002/a.bz2'), @root.join('kept')

    ask 'DRA000001', [:publish, FASTQ]
    ask 'DRA000002', [:publish, 'fastq/DRA000/DRA000002/DRX000002/a.bz2']
    move!

    assert_equal ["writable by others than its owner: #{FASTQ}", 'linked elsewhere: fastq/DRA000/DRA000002/DRX000002/a.bz2'], settled.map(&:error)
    assert_not @public.join('fastq').exist?
  end

  test "what is not a request is passed over, and one that is not a request's shape fails" do
    put @requests.root.join('notes.json'), '{}'
    put @requests.root.join('20261029T000000000000-DRA000001-publish.json'), '[]'
    put @requests.root.join('20261029T000000000001-DRA000002-publish.json'), JSON.generate(submission: 'DRA000002', action: 'publish', moves: ['x'])
    put @requests.root.join('20261029T000000000002-DRA000003-publish.json'), JSON.generate(submission: 'DRA000009', action: 'publish', moves: [])

    move!

    assert @requests.root.join('notes.json').exist?
    assert_equal ['not a request', "not a move: 'x'", 'names another submission or action than its name'], settled.map(&:error)
  end

  test 'refuses requests whose done or failed is a link' do
    elsewhere = @root.join('elsewhere').tap(&:mkpath)
    @requests.root.join('done').make_symlink(elsewhere)

    ask 'DRA000001', [:publish, FASTQ]

    output, status = mover

    assert_not status.success?
    assert_match 'not a directory, or a link: done', output
    assert_empty elsewhere.children
  end

  test 'refuses trees and a hold not on one filesystem' do
    output, status = mover(private: '/proc/sys')

    assert_not status.success?
    assert_match 'not on one filesystem', output
  end

  test 'refuses a hold others can reach' do
    @hold.chmod 0o750

    output, status = mover

    assert_not status.success?
    assert_match "the hold is to be this account's alone", output
  end

  # The repository's account would otherwise put another in its place.
  test 'refuses a private tree or requests in a directory others can write' do
    shared  = @root.join('shared').tap(&:mkpath).tap { it.chmod(0o775) }
    private = shared.join('dra').tap(&:mkpath)

    output, status = mover(private:)

    assert_not status.success?
    assert_match "#{shared} is writable by others than its owner", output
  end

  test 'one run at a time, and a run that does not end is said' do
    File.open(@root.join('mover.lock'), 'a+') do |lock|
      lock.flock File::LOCK_EX

      ask 'DRA000001', [:publish, FASTQ]

      assert_match 'another run holds the lock', move!

      lock.truncate 0
      lock.write 1.day.ago.to_f.to_s
      lock.flush

      output, status = mover

      assert_not status.success?
      assert_match 'another run has held the lock since', output
    end

    assert_equal 1, @requests.root.glob('*.json').size
  end

  # Killed between going into the hold and on out of it.
  test 'what a run left in the hold is found, and said' do
    put @hold.join('1-2-3')
    put @hold.join('1-2-3.where'), JSON.generate(op: 'publish', tree: 'dra', path: FASTQ)

    ask 'DRA000001', [:publish, FASTQ]

    assert_match "dra: in the hold as 1-2-3: publish #{FASTQ}", move!
    assert_equal "in neither tree: dra/#{FASTQ}; it is in the hold as 1-2-3", settled.sole.error
  end

  test 'takes out no more in a day than it is let' do
    put @public.join(FASTQ), 'x' * 600
    put @public.join(SRA), 'x' * 600

    ask 'DRA000001', [:withdraw, FASTQ], [:withdraw, SRA], action: :withdraw

    output, status = mover('--withdraw-limit-tb', '0.000000001')

    assert status.success?, output
    assert @private.join(FASTQ).exist?
    assert @public.join(SRA).exist?
    assert_equal "would take out more than 1000 bytes today (--withdraw-limit-tb): #{SRA}", settled.sole.error
  end

  test 'refuses a private tree under a link' do
    @root.join('elsewhere').make_symlink(@root)

    output, status = mover(private: @root.join('elsewhere', 'private'))

    assert_not status.success?
    assert_match "#{@root.join('elsewhere')} is a link", output
  end
end
