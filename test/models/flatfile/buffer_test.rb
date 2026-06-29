require 'test_helper'

class Flatfile::BufferTest < ActiveSupport::TestCase
  test 'wraps a single line to 80 columns' do
    io = StringIO.new

    Flatfile::Buffer.new(io).tap {|buf|
      buf << '                     /note="' + ('ACGT' * 30) + '"'
      buf.flush
    }

    lines = io.string.lines(chomp: true)

    assert_operator lines.size, :>, 1
    assert lines.all? { it.size <= 80 }, 'every wrapped line must be <= 80 chars'
    assert_equal lines.join.delete(' '), '/note="' + ('ACGT' * 30) + '"'
  end

  # 巨大な qualifier 値（数百 KB の継ぎ目なし 1 行）でも落ちないこと。
  # wrap が再帰実装だった頃はここで SystemStackError になり、apply ジョブが
  # request を applying のまま取り残していた。
  test 'wraps an extremely long line without overflowing the stack' do
    io = StringIO.new

    assert_nothing_raised do
      Flatfile::Buffer.new(io).tap {|buf|
        buf << '                     /note="' + ('A' * 1_000_000) + '"'
        buf.flush
      }
    end

    assert io.string.lines(chomp: true).all? { it.size <= 80 }
  end

  # COMMENT 内に埋め込んだ feature table の行は indent が 40 桁を超えることがある。
  # 値が空白で折り返せない（化学名など）と、折り返し位置が indent 内に落ちて行が
  # 縮まず、wrap が無限ループ（再帰実装では SystemStackError）になっていた。
  test 'wraps a deeply indented unbreakable value without looping forever' do
    io   = StringIO.new
    line = '            FT' + (' ' * 31) + ('(2S,4R)-1-[29-' * 50) # indent 45 桁, 空白なし

    assert_operator line.size, :>, 80

    Flatfile::Buffer.new(io).tap {|buf|
      buf << line
      buf.flush
    }

    lines = io.string.lines(chomp: true)

    assert_operator lines.size, :>, 1
    assert lines.all? { it.size <= 80 }, 'every wrapped line must be <= 80 chars'
  end
end
