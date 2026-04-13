class LoadTaxdumpJob < ApplicationJob
  def perform
    path = Rails.root.join('storage/taxdump.tar.gz')
    conn = Taxdump::Record.connection

    Dir.mktmpdir do |tmp|
      system 'tar', '-xzf', path.to_s, '-C', tmp, exception: true

      conn.execute 'DROP TABLE IF EXISTS new_names'
      conn.execute 'DROP TABLE IF EXISTS new_nodes'

      conn.execute <<~SQL
        CREATE TABLE new_names (
          id         bigserial PRIMARY KEY,
          name_class varchar   NOT NULL,
          name_txt   varchar   NOT NULL,
          tax_id     bigint    NOT NULL
        )
      SQL

      conn.execute <<~SQL
        CREATE TABLE new_nodes (
          id            bigserial PRIMARY KEY,
          hidden_flag   boolean   NOT NULL,
          parent_tax_id bigint    NOT NULL,
          rank          varchar,
          tax_id        bigint    NOT NULL
        )
      SQL

      IO.foreach("#{tmp}/names.dmp", chomp: true).each_slice 10_000 do |lines|
        rows = lines.map {|line|
          tax_id, name_txt, name_class = line.split('|').values_at(0, 1, 3).map(&:strip)

          {
            tax_id:     tax_id.to_i,
            name_txt:,
            name_class:
          }
        }

        conn.execute <<~SQL
          INSERT INTO new_names (tax_id, name_txt, name_class)
          VALUES #{rows.map {|r| "(#{r[:tax_id]}, #{conn.quote(r[:name_txt])}, #{conn.quote(r[:name_class])})" }.join(', ')}
        SQL
      end

      IO.foreach("#{tmp}/nodes.dmp", chomp: true).each_slice 10_000 do |lines|
        rows = lines.map {|line|
          tax_id, parent_tax_id, rank, hidden_flag = line.split('|').values_at(0, 1, 2, 10).map(&:strip)

          {
            tax_id:        tax_id.to_i,
            parent_tax_id: parent_tax_id.to_i,
            rank:,
            hidden_flag:   hidden_flag == '1'
          }
        }

        conn.execute <<~SQL
          INSERT INTO new_nodes (tax_id, parent_tax_id, rank, hidden_flag)
          VALUES #{rows.map {|r| "(#{r[:tax_id]}, #{r[:parent_tax_id]}, #{conn.quote(r[:rank])}, #{r[:hidden_flag]})" }.join(', ')}
        SQL
      end

      conn.execute 'CREATE INDEX ON new_names (lower(name_txt), name_class)'
      conn.execute 'CREATE INDEX ON new_names (tax_id, name_class)'
      conn.execute "CREATE INDEX ON new_names (tax_id, name_txt) WHERE name_class = 'common name'"
      conn.execute "CREATE INDEX ON new_names (tax_id, name_txt) WHERE name_class = 'scientific name'"
      conn.execute 'CREATE INDEX ON new_nodes (parent_tax_id)'
      conn.execute 'CREATE INDEX ON new_nodes (tax_id)'

      conn.transaction do
        conn.execute 'ALTER TABLE names RENAME TO old_names'
        conn.execute 'ALTER TABLE nodes RENAME TO old_nodes'
        conn.execute 'ALTER TABLE new_names RENAME TO names'
        conn.execute 'ALTER TABLE new_nodes RENAME TO nodes'
      end

      conn.execute 'DROP TABLE old_names'
      conn.execute 'DROP TABLE old_nodes'
    end
  end
end
