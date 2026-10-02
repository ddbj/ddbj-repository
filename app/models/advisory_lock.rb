# A lock across processes that Postgres lets go of with the connection that
# holds it — so a process stopped under it holds nothing, which a row saying
# `running` cannot promise. Held for a session rather than a transaction, for
# work that commits as it goes, or runs for hours.
#
# What it settles is two runs of one thing at once: the job a deploy or
# RecoverKilledJobsJob runs again, and the run it replaces when that is not
# gone yet — a worker Solid Queue gave up on for missing its heartbeat goes
# on running, and a connection killed mid-statement is not let go of until
# the statement ends.
#
# Which is why a run that finds the lock held is not done: the holder may
# yet die without finishing. The jobs wait and try again
# (`retry_on AdvisoryLock::Held`), and since each carries on from what was
# committed, a run that comes after a finished one has nothing to do.
module AdvisoryLock
  class Held < StandardError; end

  module_function

  # Runs the block holding the lock `name`, or raises Held while another
  # session holds it.
  def exclusively(name)
    ActiveRecord::Base.connection_pool.with_connection do |conn|
      raise Held, "another session holds #{name}" unless lock(conn, 'pg_try_advisory_lock', name)

      begin
        yield
      ensure
        unlock conn, name
      end
    end
  end

  def lock(conn, fn, name)
    conn.select_value(ActiveRecord::Base.sanitize_sql(["SELECT #{fn}(hashtext(?))", name]))
  end

  # Not in the way of the error the block raised, if it broke the
  # connection or left a transaction aborted: the connection is thrown
  # away instead, which lets go of the lock as surely, rather than going
  # back to the pool still holding it.
  def unlock(conn, name)
    # Already thrown away — by an inner lock of the same session — or
    # broken: either way its session, and the lock with it, is gone.
    return unless conn.active?

    lock conn, 'pg_advisory_unlock', name
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn "Could not let go of #{name} (#{e.class}); dropping the connection"

    conn.throw_away!
  end

  private_class_method :lock, :unlock
end
