require 'test_helper'

class StatsTest < ActionDispatch::IntegrationTest
  # 認証不要。番号の残量は外から見えてよい情報として出している。
  test 'index reports the next number and the remaining capacity per scope' do
    Sequence.ensure_records!
    Sequence.find_by!(scope: 'jpo_na').update! prefix: 'QP', next: 42

    get stats_path

    assert_conform_schema 200

    stat = response.parsed_body['sequences'].find { it['scope'] == 'jpo_na' }

    assert_equal 'QP000042', stat['next']
    assert_equal 41,         stat['used']
    assert_equal stat['total'] - 41, stat['remaining']
  end

  # 表示が払い出しと食い違わないこと。prefix を使い切った直後は `next` がその
  # prefix の最大値を超えたまま休むので、素朴に組み立てると QP1000000 という
  # 存在し得ない番号を名乗る。
  test 'index resolves a prefix that has been used up' do
    Sequence.ensure_records!
    Sequence.find_by!(scope: 'jpo_na').update! prefix: 'QP', next: 1000000

    get stats_path

    assert_conform_schema 200

    stat = response.parsed_body['sequences'].find { it['scope'] == 'jpo_na' }

    assert_equal 'QQ000001', stat['next']
    assert_equal 999999,     stat['used']
  end

  # pad: false の scope で桁を埋めない。
  test 'index does not pad the BioProject number' do
    Sequence.ensure_records!
    Sequence.find_by!(scope: 'bp').update! next: 42366

    get stats_path

    assert_conform_schema 200

    stat = response.parsed_body['sequences'].find { it['scope'] == 'bp' }

    assert_equal 'PRJDB42366', stat['next']
  end
end
