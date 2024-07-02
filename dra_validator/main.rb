require 'bundler/setup'

Bundler.require

# DB = Sequel.connect(ENV.fetch('DATABASE_URL'))

# submissions = DB[:submission]

# submissions.insert usr_id: 42, submitter_id: '42', serial: 42

# ディレクトリ名を引数で受け取れるようにする
# 受け取った引数を元に再帰的にディレクトリを作成するメソッドを一つ用意する
# そのメソッドの中で例外処理をする

def mkdir_p!(sftp, dir)
  dir_names = dir.split('/')
  
  dir_names.size.times.map {|i|
    dir_names[0..i].join('/')
  }.each do |dir_name|
    begin
      sftp.mkdir! dir_name
    rescue Net::SFTP::StatusException => e
      raise unless e.code == 4
    end
  end
end

Net::SFTP.start 'localhost', 'maimu', key_data: [File.read('/Users/maimu/.ssh/id_ed25519_no_passphrase')] do |sftp|
  mkdir_p!(sftp, 'Documents/upload/foo/bar')
end
