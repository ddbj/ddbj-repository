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
    # Refused where the migration is not being worked on. The connection
    # details are read from the same credential the deployed app already
    # uses for the legacy Postgres, so staging and production can import
    # from D-way perfectly well — the only thing standing between a
    # production database and a curator pressing "New run" is that nobody
    # has.
    class Disabled < StandardError; end

    module_function

    # And never once D-way has handed over (DwayTakeover): what it would
    # bring back is what this system now decides.
    def enabled? = Rails.application.config_for(:app).data_migration.present? && !DwayTakeover.done?

    def refusal
      DwayTakeover.done? ? 'D-way has handed over; there is nothing to import from it.' : "Importing from D-way is switched off in #{Rails.env}."
    end

    # Checked when a connection is opened rather than when the options
    # are built: the clients freeze their options into a constant at load
    # time, so a check there would fire on autoload and take down every
    # screen that merely names the class.
    def ensure_enabled!
      return if enabled?

      raise Disabled, refusal
    end

    # A connection to D-way's schema, its timestamps coming back as text in
    # the ISO order `time` reads whatever the server's own DateStyle. Set
    # once connected rather than as a startup option, which a pooler in
    # front of the server may refuse.
    def connect(options)
      PG.connect(**options).tap {|conn|
        conn.exec('SET search_path TO mass')
        conn.exec('SET DateStyle TO ISO')
      }
    end

    # D-way's timestamps are without a zone, and are Tokyo's wall clock.
    # Read as such here, where they come in: a column written with
    # `update_columns` is not converted on the way, and would take the
    # text for UTC.
    #
    # What does not read as a time (`infinity`) is refused rather than
    # taken for none.
    def time(text)
      return nil if text.nil?

      Time.find_zone!('Asia/Tokyo').parse(text) or raise ArgumentError, "not a D-way timestamp: #{text.inspect}"
    end

    # When what is public about a row last changed, as far as D-way can say
    # (DB-2096's `last_published_at`):
    #
    #   - public: its dist_date — or, for one made public before D-way kept
    #     that (status 700), its last change
    #   - out of public: D-way kept no moment for the leaving, and dist_date
    #     does not move then, so the row's last change stands in, which is
    #     no earlier than it (DB-2096 dates the same retrofit by the
    #     suppress list's date)
    #   - never public: none
    def last_published_at(public:, release:, dist:, modified:)
      return dist || modified if public

      [dist, modified].compact.max if release || dist
    end

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

    # 接続先そのものを記録するための指紋。
    #
    # 「どのデータベースから取り込んだのか」が後から分からないと、staging の
    # テスト行や古い値を production のデータだと思って判断してしまう。実際に
    # やった。host / port はトンネル越しだと双方 localhost:54301 になり得るので
    # 区別に使えない。サーバ自身に名乗らせる (`inet_server_addr` はサーバから見た
    # 自分のアドレスなので、トンネルの手前と奥で値が違う)。
    #
    # 行数の見積りは pg_class.reltuples を使う。count(*) は 200 万行で seq scan に
    # なるが、reltuples は統計から即座に返る。桁が違えば取り違えに気付ける。
    def fingerprint(conn, tables:)
      row = conn.exec(<<~SQL).first
        SELECT current_database()               AS database,
               host(inet_server_addr())         AS server_addr,
               inet_server_port()::text         AS server_port,
               split_part(version(), ' on ', 1)  AS server_version
      SQL

      row.merge('rows' => tables.to_h {|table|
        [table, conn.exec_params(<<~SQL, [table]).first['n']&.to_i]
          SELECT reltuples::bigint AS n FROM pg_class WHERE oid = to_regclass($1)
        SQL
      })
    end

    def parse_xsmdb_credential
      url = Rails.application.credentials.dig(:database_url, :xsmdb)
      URI.parse(url) if url
    end
  end
end
