#!/usr/bin/env ruby
# frozen_string_literal: true

# SeaweedFS S3 load reproducer.
#
# Two run modes:
#
#   1) Rails-loaded (defaults come from config/seaweedfs.yml):
#      bin/kamal app exec -d dev \
#        "bin/rails runner script/seaweedfs_load.rb --concurrency 12 --op put"
#
#   2) Standalone (no Rails; pass endpoint + creds explicitly):
#      bundle exec ruby script/seaweedfs_load.rb \
#        --endpoint http://localhost:8333 --access-key K --secret-key S \
#        --concurrency 12 --op put
#
# The mode-2 form is what you'd run from INSIDE the SeaweedFS host so
# kamal-proxy and the WAN hop are out of the picture — that's the
# clearest way to prove whether the hang is upstream of Weed itself.
#
# Toggles:
#   --endpoint URL         SeaweedFS S3 endpoint
#   --bucket NAME          default: uploads
#   --access-key K
#   --secret-key K
#   --region NAME          default: us-east-1
#   --concurrency N        parallel threads (default 8)
#   --size BYTES           PUT body size (default 7168 ≈ importer patch shape)
#   --count N              total ops (default 200)
#   --op put|get|mixed     default put; get / mixed need --seed-key
#   --seed-key K           existing key to GET
#   --timeout SECONDS      per-op HTTP timeout (default 30)
#   --key-prefix PATH      default: repro/<timestamp>-<pid>
#
# Emits per-second progress on stderr and a final summary
# (p50/p95/p99/max, throughput, error breakdown) on stdout.

require 'optparse'
require 'securerandom'
require 'aws-sdk-s3'

opts = {
  endpoint:          nil,
  bucket:            'uploads',
  access_key:        nil,
  secret_key:        nil,
  region:            'us-east-1',
  concurrency:       8,
  size:              7 * 1024,
  count:             200,
  op:                'put',
  seed_key:          nil,
  timeout:           30.0,
  key_prefix:        nil,
  progress_interval: 1.0
}

OptionParser.new {|o|
  o.on('--endpoint URL')            {|v| opts[:endpoint]   = v }
  o.on('--bucket NAME')             {|v| opts[:bucket]     = v }
  o.on('--access-key KEY')          {|v| opts[:access_key] = v }
  o.on('--secret-key KEY')          {|v| opts[:secret_key] = v }
  o.on('--region NAME')             {|v| opts[:region]     = v }
  o.on('--concurrency N', Integer)  {|v| opts[:concurrency] = v }
  o.on('--size BYTES', Integer)     {|v| opts[:size]       = v }
  o.on('--count N', Integer)        {|v| opts[:count]      = v }
  o.on('--op OP')                   {|v| opts[:op]         = v }
  o.on('--seed-key KEY')            {|v| opts[:seed_key]   = v }
  o.on('--timeout SECONDS', Float)  {|v| opts[:timeout]    = v }
  o.on('--key-prefix P')            {|v| opts[:key_prefix] = v }
}.parse!

# Rails-loaded mode: pull unset fields from config/seaweedfs.yml.
if defined?(Rails) && Rails.application
  cfg = Rails.application.config_for(:seaweedfs) rescue nil
  if cfg
    opts[:endpoint]   ||= cfg.endpoint
    opts[:access_key] ||= cfg.access_key
    opts[:secret_key] ||= cfg.secret_key
  end
end

abort '--endpoint required (or run via bin/rails runner to inherit config/seaweedfs.yml)' unless opts[:endpoint]
abort '--access-key required' unless opts[:access_key]
abort '--secret-key required' unless opts[:secret_key]
abort "--op must be one of put|get|mixed (got #{opts[:op].inspect})" unless %w[put get mixed].include?(opts[:op])
abort "--seed-key required for op=#{opts[:op]}" if %w[get mixed].include?(opts[:op]) && opts[:seed_key].nil?

opts[:key_prefix] ||= "repro/#{Time.now.to_i}-#{Process.pid}"

client = Aws::S3::Client.new(
  endpoint:          opts[:endpoint],
  access_key_id:     opts[:access_key],
  secret_access_key: opts[:secret_key],
  region:            opts[:region],
  force_path_style:  true,
  http_open_timeout: opts[:timeout],
  http_read_timeout: opts[:timeout],

  # Disable SDK retries so hangs show up as raw errors instead of being
  # papered over — we want to see the first failure edge, not a retry
  # storm.
  retry_limit: 0
)

payload = SecureRandom.random_bytes(opts[:size])
queue   = Queue.new
opts[:count].times {|i| queue << i }

mutex     = Mutex.new
latencies = []
errors    = []

monotonic = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
run_start = monotonic.call

progress_stop   = false
progress_thread = Thread.new do
  last_total = 0
  until progress_stop
    sleep opts[:progress_interval]
    ok, err = mutex.synchronize { [latencies.size, errors.size] }
    total   = ok + err
    delta   = total - last_total
    last_total = total
    warn format(
      '[%6.2fs] ok=%d err=%d rate=%.1f/s in-flight~%d',
      monotonic.call - run_start,
      ok,
      err,
      delta / opts[:progress_interval],
      opts[:count] - total - queue.size
    )
  end
end

do_op = lambda do |tid|
  key = "#{opts[:key_prefix]}/#{tid}/#{SecureRandom.hex(8)}"
  case opts[:op]
  when 'put'
    client.put_object(bucket: opts[:bucket], key: key, body: payload)
  when 'get'
    client.get_object(bucket: opts[:bucket], key: opts[:seed_key])
  when 'mixed'
    if rand < 0.5
      client.put_object(bucket: opts[:bucket], key: key, body: payload)
    else
      client.get_object(bucket: opts[:bucket], key: opts[:seed_key])
    end
  end
end

threads = opts[:concurrency].times.map do |tid|
  Thread.new do
    loop do
      begin
        queue.pop(true)
      rescue ThreadError
        break
      end

      t0 = monotonic.call
      begin
        do_op.call(tid)
        dt = (monotonic.call - t0) * 1000
        mutex.synchronize { latencies << dt }
      rescue StandardError => e
        dt = (monotonic.call - t0) * 1000
        mutex.synchronize { errors << [dt, e.class.name, e.message.to_s.byteslice(0, 200)] }
      end
    end
  end
end

threads.each(&:join)
progress_stop = true
progress_thread.join

total_elapsed = monotonic.call - run_start
sorted        = latencies.sort

# Nearest-rank percentile.
pct = ->(p) {
  next 0.0 if sorted.empty?

  idx = (p * sorted.size).ceil - 1
  sorted[idx.clamp(0, sorted.size - 1)]
}

puts
puts '=== summary ==='
puts "endpoint    : #{opts[:endpoint]}"
puts "bucket      : #{opts[:bucket]}"
puts "op          : #{opts[:op]}"
puts "size        : #{opts[:size]} bytes"
puts "concurrency : #{opts[:concurrency]}"
puts "count       : #{opts[:count]}"
puts "elapsed     : #{format('%.2fs', total_elapsed)}"
puts "ok          : #{latencies.size}"
puts "err         : #{errors.size}"

if latencies.any?
  puts "throughput  : #{format('%.1f ops/s', latencies.size / total_elapsed)}"
  puts "latency ms  : p50=#{format('%.1f', pct.call(0.50))} " \
                    "p95=#{format('%.1f', pct.call(0.95))} " \
                    "p99=#{format('%.1f', pct.call(0.99))} " \
                    "max=#{format('%.1f', sorted.last)}"
end

if errors.any?
  by_class = errors.group_by { it[1] }.transform_values(&:size)
  puts "err classes : #{by_class.map {|k, v| "#{k}=#{v}" }.join(', ')}"
  puts 'first errors:'
  errors.first(3).each {|dt, klass, msg| puts "  #{format('%.1f', dt)}ms #{klass}: #{msg}" }
end
