class Taxdump::Node < Taxdump::Record
  def self.ancestor_names(tax_ids)
    sql = sanitize_sql_array([<<~SQL, tax_ids])
      WITH RECURSIVE chain(seed_tax_id, tax_id, parent_tax_id, hidden_flag, depth) AS (
        SELECT v.tax_id, n.tax_id, n.parent_tax_id, n.hidden_flag, 0
        FROM nodes AS n
        JOIN unnest(ARRAY[?]::int[]) AS v(tax_id) ON v.tax_id = n.tax_id
        WHERE n.tax_id <> 1

        UNION ALL

        SELECT c.seed_tax_id, p.tax_id, p.parent_tax_id, p.hidden_flag, c.depth + 1
        FROM chain AS c
        JOIN nodes AS p ON p.tax_id = c.parent_tax_id
        WHERE p.tax_id <> 1
      )
      SELECT c.seed_tax_id, nm.name_txt
      FROM chain AS c
      JOIN names AS nm ON nm.tax_id = c.tax_id
      WHERE nm.name_class = 'scientific name'
        AND c.hidden_flag = FALSE
        AND c.depth > 0
      ORDER BY c.seed_tax_id, c.depth DESC;
    SQL

    connection.select_rows(sql).each_with_object(Hash.new {|h, k| h[k] = [] }) {|(seed_tax_id, name_txt), memo|
      memo[seed_tax_id] << name_txt
    }
  end
end
