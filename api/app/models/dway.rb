class Dway
  include Singleton

  class << self
    delegate :submitterdb, :drmdb, :bioproject, to: :instance
  end

  def submitterdb
    @submitterdb ||= Sequel.connect(ENV.fetch('SUBMITTERDB_DATABASE_URL'))
  end

  def drmdb
    @drmdb ||= Sequel.connect(ENV.fetch('DRMDB_DATABASE_URL'))
  end

  def bioproject
    @bioproject ||= Sequel.connect(ENV.fetch('BIOPROJECT_DATABASE_URL'))
  end
end
