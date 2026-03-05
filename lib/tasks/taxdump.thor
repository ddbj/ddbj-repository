# vim: ft=ruby

require_relative '../../config/environment'

class TaxdumpTasks < Thor
  include Thor::Actions

  namespace :taxdump

  def self.exit_on_failure? = true

  desc 'load', 'Load the taxdump data into the database'
  def load
    Dir.mktmpdir do |tmp|
      run "tar -xzf - -C #{tmp}"

      Taxdump::Record.connection.truncate Taxdump::Name.table_name
      Taxdump::Record.connection.truncate Taxdump::Node.table_name

      IO.foreach("#{tmp}/names.dmp", chomp: true).each_slice 10_000 do |lines|
        Taxdump::Name.insert_all lines.map {|line|
          tax_id, name_txt, name_class = line.split('|').values_at(0, 1, 3).map(&:strip)

          {
            tax_id:     tax_id.to_i,
            name_txt:,
            name_class:
          }
        }
      end

      IO.foreach("#{tmp}/nodes.dmp", chomp: true).each_slice 10_000 do |lines|
        Taxdump::Node.insert_all lines.map {|line|
          tax_id, parent_tax_id, rank, hidden_flag = line.split('|').values_at(0, 1, 2, 10).map(&:strip)

          {
            tax_id:        tax_id.to_i,
            parent_tax_id: parent_tax_id.to_i,
            rank:,
            hidden_flag:   hidden_flag == '1'
          }
        }
      end
    end
  end
end
