RSpec.configure do |config|
  config.around do |example|
    Dir.mktmpdir do |repository_dir|
      env = {
        DDBJ_VALIDATOR_URL: 'http://validator.example.com/api',
        REPOSITORY_DIR:     repository_dir,
        USER_HOME_DIR:      "#{file_fixture_path}/home"
      }

      ClimateControl.modify env, &example
    end
  end
end
