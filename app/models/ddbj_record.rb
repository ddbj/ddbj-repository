module DDBJRecord
  def self.parse(io)
    Handler.new.tap { Oj.saj_parse(it, io) }.result
  end
end
