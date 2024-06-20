require 'bundler/setup'

Bundler.require

# DB = Sequel.connect(ENV.fetch('DATABASE_URL'))

# submissions = DB[:submission]

# submissions.insert usr_id: 42, submitter_id: '42', serial: 42

Net::SSH.start 'localhost', 'ursm', key_data: [File.read('/home/ursm/.ssh/id_25519_no_passphrase')] do |ssh|
  puts ssh.exec!('uname -a')
end
