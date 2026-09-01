require 'test_helper'

class PublicXML::Bs::BioSampleRendererTest < ActiveSupport::TestCase
  # bsbatch の公開 XML は accession ごとに保存された XML を連結して
  # Contacts を消すだけなので、保存されている実物がそのまま公開される形に
  # なる。test/fixtures/files/biosample/SSUB000019_db_ok.xml がその実物。
  FIXTURE = Rails.root.join('test/fixtures/files/biosample/SSUB000019_db_ok.xml')

  # bscommon から持ってきた公開 XML のスキーマ。持っていないと「出せたか
  # どうか」しか見られず、出したものが読めるかは誰も見ていないことになる。
  SCHEMA = Nokogiri::XML::Schema(Rails.root.join('test/fixtures/files/biosample/biosample.1.2.0.xsd').read)

  test 'reproduces the stored D-way XML for everything v3 can express' do
    stored = Nokogiri::XML(FIXTURE.read).at_xpath('//BioSample')

    # 公開時に落ちるもの (Contacts) と、v3 に取り込んでいないので出せない
    # もの (Links = mass.publications / mass.link)。後者は import 側の穴。
    stored.at_xpath('./Owner/Contacts').remove
    stored.at_xpath('./Links').remove

    node = render(stored)

    assert_equal stored.element_children.map { canonical(it) }, node.element_children.map { canonical(it) }

    # 日付だけは一致しない。D-way の列は timestamp で、こちらは import の
    # 時点で ::date に落としてあるため。
    assert_equal 'public', node['access']
    assert_equal '2014-03-20T10:32:03.806+09:00', stored['last_update']
    assert_equal '2014-03-20T00:00:00+09:00',     node['last_update']
  end

  test 'the rendered element validates against the published schema' do
    assert_empty SCHEMA.validate(document_of(render(sample, **full_record_overrides)))
  end

  test 'emits the BioSample shape D-way publishes; suppresses Owner Contacts' do
    node = render(sample(release_date: Date.new(2026, 3, 1), dist_date: Date.new(2026, 6, 1)))

    assert_equal 'BioSample', node.name
    assert_equal 'public',    node['access']
    assert_equal '2026-03-01T00:00:00+09:00', node['publication_date']
    assert_equal '2026-06-01T00:00:00+09:00', node['last_update']
    assert_nil   node['accession'], 'the accession is an Id, not an attribute of BioSample'

    id = node.at_xpath('./Ids/Id')

    assert_equal 'SAMD00000777', id.text
    assert_equal 'BioSample',    id['namespace']
    assert_equal '1',            id['is_primary']
    assert_equal 1,              node.xpath('./Ids/Id').size, 'v3 carries no external identifiers'

    desc = node.at_xpath('./Description')

    assert_equal %w[SampleName Title Organism Comment], desc.element_children.map(&:name)
    assert_equal 'a-sample',             desc.at_xpath('./SampleName').text
    assert_equal 'A sample title',       desc.at_xpath('./Title').text
    assert_equal '9606',                 desc.at_xpath('./Organism/@taxonomy_id').value
    assert_equal 'Homo sapiens',         desc.at_xpath('./Organism/OrganismName').text
    assert_equal 'A sample description', desc.at_xpath('./Comment/Paragraph').text

    assert_equal 'DDBJ',                   node.at_xpath('./Owner/Name').text
    assert_equal 'https://ddbj.nig.ac.jp', node.at_xpath('./Owner/Name/@url').value
    assert_nil   node.at_xpath('./Owner/Contacts'), 'BS public XML must strip Contacts (bsbatch parity)'

    assert_equal 'MIxS.air.5.0', node.at_xpath('./Models/Model').text
    assert_nil   node.at_xpath('./Package'), '<Package> is NCBI-flavoured and is not in the BioSample schema'
  end

  # Description に持ち上げた属性は bag から取り除かれる。D-way は
  # DescriptionConverter で pop してから <Attributes> を書くので、公開
  # XML に同じ値が二度現れることはない。sample_name だけは戻されて先頭に
  # 来る。
  test 'attributes lifted into Description are not repeated in Attributes' do
    attrs = attributes_of(render(sample))

    assert_equal [
      ['sample_name',     'a-sample'],
      ['collection_date', '2026-03-01'],
      ['geo_loc_name',    'Japan']
    ], attrs
  end

  # 持ち上げるのは最初の 1 行だけ (AttributesOperator#pop)。名前で全部
  # 落とすと、D-way が <Attributes> に残していた 2 行目以降が消える。
  test 'only the first row of a lifted name is lifted; later duplicates stay attributes' do
    node = render(sample, attributes: [
      {'name' => 'description', 'value' => 'first'},
      {'name' => 'description', 'value' => 'second'}
    ])

    assert_equal 'first', node.at_xpath('./Description/Comment/Paragraph').text

    assert_equal [
      ['sample_name', 'a-sample'],
      ['description', 'second']
    ], attributes_of(node)
  end

  # sample_comment は v3 の typed slot が無い。bag から取り除いたうえで
  # 誰も書かなければ、値はファイルから消える。D-way は description と
  # 並べて 2 つ目の Paragraph にしていた。
  test 'sample_comment is published as a second Paragraph, not dropped' do
    node = render(sample, attributes: [
      {'name' => 'description',    'value' => 'the description'},
      {'name' => 'sample_comment', 'value' => 'the comment'}
    ])

    assert_equal ['the description', 'the comment'], node.xpath('./Description/Comment/Paragraph').map(&:text)
  end

  # 名前か値が空の行は落とす (AttributeConverter#hasValue)。
  test 'attributes missing a name or a value are not published' do
    node = render(sample, attributes: [
      {'name' => 'strain', 'value' => '  '},
      {'name' => '',       'value' => 'nameless'},
      {'name' => 'depth',  'value' => '0m'}
    ])

    assert_equal [['sample_name', 'a-sample'], ['depth', '0m']], attributes_of(node)
  end

  # organism がどこにも無くても <OrganismName> は書く。要素が無いと
  # schema エラーになり、validator が「organism が無い」と言う前に落ちる。
  test 'a sample with no organism still gets an empty OrganismName' do
    node = render(sample, organism: nil, attributes: [])

    assert_equal '', node.at_xpath('./Description/Organism/OrganismName').text
    assert_nil       node.at_xpath('./Description/Organism/@taxonomy_id')
  end

  # taxonomy_id は xs:positiveInteger。staging には 'unknown' のような値が
  # あり、それを載せると読める XML でなくなる。
  test 'a taxonomy_id that is not a positive integer is not published' do
    ['unknown', '0', ''].each do |value|
      node = render(sample, organism: {'name' => 'Homo sapiens'}, attributes: [
        {'name' => 'taxonomy_id', 'value' => value},
        {'name' => 'depth',       'value' => '0m'}
      ])

      assert_nil node.at_xpath('./Description/Organism/@taxonomy_id'), "published taxonomy_id=#{value.inspect}"
      assert_empty SCHEMA.validate(document_of(node)), "taxonomy_id=#{value.inspect} produced invalid XML"
    end
  end

  # <Owner> は必須。D-way は organization が無ければ空の <Name> を出して
  # いた。落とすと後続の要素の位置がずれて文書ごと読めなくなる。
  test 'Owner is written even when the submission names no organization' do
    node = render(sample, submitters: [{'first_name' => 'Ada'}])

    assert_equal '',       node.at_xpath('./Owner/Name').text
    assert_empty SCHEMA.validate(document_of(node))
  end

  # 再配布されていない sample の last_update は「最後に直した日」。
  # release_date に落とすと、直したのに更新を通知しないことになる。
  test 'last_update falls back to modified_date, not to the release' do
    node = render(sample(release_date: Date.new(2014, 3, 1), dist_date: nil, modified_date: Date.new(2019, 7, 20)))

    assert_equal '2014-03-01T00:00:00+09:00', node['publication_date']
    assert_equal '2019-07-20T00:00:00+09:00', node['last_update']
  end

  test 'returns nil when the v3 record has no sample with a matching alias' do
    record = {'samples' => [{'alias' => 'no-such-alias'}]}

    assert_nil PublicXML::Bs::BioSampleRenderer.new(record:, row: sample).call
  end

  private

  def sample(**overrides)
    Sample.new({
      accession:     'SAMD00000777',
      sample_name:   'a-sample',
      release_date:  Date.new(2026, 3, 1),
      dist_date:     Date.new(2026, 6, 1),
      modified_date: Date.new(2026, 6, 1)
    }.merge(overrides))
  end

  def attributes_of(node)
    node.xpath('./Attributes/Attribute').map { [it['attribute_name'], it.text] }
  end

  def document_of(node)
    Nokogiri::XML(node.to_xml)
  end

  # 比較するのは中身であって整形ではない。空白だけのテキストノードを落と
  # してから C14N にかけると、インデントと属性の並び順の差が消える。
  def canonical(node)
    copy = node.dup
    copy.xpath('.//text()').each { it.remove if it.text.strip.empty? }
    copy.canonicalize
  end

  # BioSample::Converter が書くのと同じ形の v3 record。持ち上げた値は
  # attribute bag にも残る (Converter の lift-but-retain) ので、重複を
  # 落とすのは renderer の仕事になる。
  def full_record_overrides
    {
      'title'       => 'A sample title',
      'description' => 'A sample description',
      'organism'    => {'taxonomy_id' => 9606, 'name' => 'Homo sapiens'},

      'attributes' => [
        {'name' => 'sample_name',     'value' => 'a-sample'},
        {'name' => 'sample_title',    'value' => 'A sample title'},
        {'name' => 'description',     'value' => 'A sample description'},
        {'name' => 'organism',        'value' => 'Homo sapiens'},
        {'name' => 'taxonomy_id',     'value' => '9606'},
        {'name' => 'collection_date', 'value' => '2026-03-01'},
        {'name' => 'geo_loc_name',    'value' => 'Japan'}
      ]
    }
  end

  def render(row, submitters: nil, **overrides)
    return render_stored(row) if row.is_a?(Nokogiri::XML::Node)

    record = {
      'submission' => {
        'submitters' => submitters || [{
          'email'         => 'curator@example.com',
          'first_name'    => 'Ada',
          'organizations' => [{'name' => 'DDBJ', 'url' => 'https://ddbj.nig.ac.jp'}]
        }]
      },

      'samples' => [{
        'accession' => row.accession,
        'alias'     => row.sample_name,
        'package'   => 'MIxS.air.5.0'
      }.merge(full_record_overrides).merge(overrides.transform_keys(&:to_s))]
    }

    PublicXML::Bs::BioSampleRenderer.new(record:, row:).call
  end

  # 保存されている実物から v3 record を組み立てて描き直す。attribute bag
  # は公開 XML から持ち上げ済みの行が抜けているので、Converter が書くのと
  # 同じように <Description> の値を戻してやる。
  def render_stored(stored)
    org  = stored.at_xpath('./Owner/Name')
    desc = stored.at_xpath('./Description')
    bag  = stored.xpath('./Attributes/Attribute').map { {'name' => it['attribute_name'], 'value' => it.text} }

    lifted = [
      ['sample_title', desc.at_xpath('./Title')&.text],
      ['organism',     desc.at_xpath('./Organism/OrganismName')&.text],
      ['taxonomy_id',  desc.at_xpath('./Organism/@taxonomy_id')&.value],
      ['description',  desc.at_xpath('./Comment/Paragraph')&.text]
    ].filter_map {|name, value| {'name' => name, 'value' => value} if value.present? }

    row = Sample.new(
      accession:     stored.at_xpath('./Ids/Id[@namespace="BioSample"]').text,
      sample_name:   desc.at_xpath('./SampleName').text,
      modified_date: Date.new(2014, 3, 20)
    )

    record = {
      'submission' => {'submitters' => [{'organizations' => [{'name' => org.text, 'url' => org['url']}]}]},

      'samples' => [{
        'accession'  => row.accession,
        'alias'      => row.sample_name,
        'package'    => stored.at_xpath('./Models/Model').text,
        'attributes' => bag + lifted
      }]
    }

    PublicXML::Bs::BioSampleRenderer.new(record:, row:).call
  end
end
