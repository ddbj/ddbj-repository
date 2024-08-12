class Dway
  include Singleton

  class << self
    delegate :bioproject, :drmdb, :submitterdb, to: :instance
  end

  def bioproject
    @bioproject ||= Sequel.connect(ENV.fetch("BIOPROJECT_DATABASE_URL"), search_path: "mass")
  end

  def drmdb
    @drmdb ||= Sequel.connect(ENV.fetch("DRMDB_DATABASE_URL"), search_path: "mass")
  end

  def submitterdb
    @submitterdb ||= Sequel.connect(ENV.fetch("SUBMITTERDB_DATABASE_URL"), search_path: "mass")
  end
end
