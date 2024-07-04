class Dway
  include Singleton

  class << self
    delegate :submitter_db, :drmdb, to: :instance
  end

  def submitter_db
    @submitter_db ||= Sequel.connect(ENV.fetch('SUBMITTER_DB_DATABASE_URL'))
  end

  def drmdb
    @drmdb ||= Sequel.connect(ENV.fetch('DRMDB_DATABASE_URL'))
  end
end
