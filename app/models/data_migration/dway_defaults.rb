# frozen_string_literal: true

module DataMigration
  # Default libpq connection options for the D-way legacy Postgres,
  # shared by BioProject::StagingClient and BioSample::StagingClient.
  #
  # Precedence per field: explicit `DWAY_*` env var (local SSH tunnel
  # override) → parsed `database_url.xsmdb` credential (deployed apps
  # already point this URL at the same Postgres instance, so we read
  # host/port/user/password from there instead of duplicating them as
  # separate `dway_db_password` etc. credentials) → hardcoded default
  # (only reached in local development, where the user runs an SSH
  # tunnel to localhost:54301 and supplies DWAY_DB_PASSWORD inline).
  module DwayDefaults
    module_function

    def options(dbname:)
      xsmdb = parse_xsmdb_credential

      {
        host:     ENV['DWAY_PGHOST']       || xsmdb&.host     || 'localhost',
        port:     ENV['DWAY_PGPORT']&.to_i || xsmdb&.port     || 54301,
        user:     ENV['DWAY_PGUSER']       || xsmdb&.user     || 'const',
        dbname:   dbname,
        password: ENV['DWAY_DB_PASSWORD']  || xsmdb&.password
      }
    end

    def parse_xsmdb_credential
      url = Rails.application.credentials.dig(:database_url, :xsmdb)
      URI.parse(url) if url
    end
  end
end
