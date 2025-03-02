RSpec.configure do |config|
  config.around do |example|
    Dir.mktmpdir do |repository_dir|
      env = {
        DDBJ_VALIDATOR_URL:     "http://validator.example.com/api",
        MASS_DIR_PATH_TEMPLATE: "#{file_fixture_path}/submission/{user}",
        REPOSITORY_DIR:         repository_dir
      }

      ClimateControl.modify env, &example
    end
  end
end
