
require 'optparse'
require 'net/http'
require 'uri'
require 'etc'
require 'socket'
require 'yaml'
require 'yaml/store'

cmd = ARGV.shift

WORKING_DIR = File.expand_path(ENV['BUILD_RUBY_WORKING_DIR'] || "~/ruby")
BUILD_RUBY_SCRIPT = File.join(File.dirname(__FILE__), 'build-ruby.rb')
PAGER = ENV['PAGER'] || 'less'

def (DummyCollector = Object.new).<<(obj)
  # ignore
end

# load TARGETS
targets_yaml = File.join(WORKING_DIR, 'targets.yaml')
if File.exist?(targets_yaml)
  TARGETS = YAML.load(File.read(targets_yaml))
else
  TARGETS = {}
end
Dir.glob(File.join(WORKING_DIR, '*.br')){|file|
  target = File.basename(file, '.br')
  TARGETS[target] = File.read(file)
}

# setup params
TARGETS.each{|target, config|
  TARGETS[target] = config ? config.split("\n") : []
}

def build target, extra_opts: ARGV, result_collector: DummyCollector, build_timeout: (60 * 60 * 2) # 2 hours
  opts = []
  # opts by default
  opts << "--target_name=#{target}"
  logfile = File.join(WORKING_DIR, 'logs', "brlog.#{target}.#{Time.now.strftime('%Y%m%d-%H%M%S')}")
  opts << "--logfile=#{logfile}"
  opts << "--timeout=#{build_timeout}"

  # opts from config file
  opts.concat(TARGETS[target])

  # opts from command line
  opts.concat extra_opts

  begin
    IO.popen("ruby #{BUILD_RUBY_SCRIPT} #{opts.join(' ')}", 'r', err: [:child, :out]){|io|
      while line = io.gets
        result_collector << line
        puts line
      end
    }
  rescue SystemCallError => e
    line = "br.rb: #{e.inspect}"
    result_collector << line
    puts line
  end

  result = if $?.success?
             'OK'
           else
             'NG'
           end
  [result, logfile]
end

def clean_all target
  build target, extra_opts: ['--rm=all']
end

def check_logfile logfile
  r = {
    exit_results: [],
    rev: nil,
    test_all: nil,
    test_all_log: [],
    test_spec: nil,
  }

  cmd = nil
  test_all_logging_lines = 0

  open(logfile){|f|
    f.each_line{|line|
      case
      when /INFO -- : \$\$\$\[beg\] (.+)/ =~ line
        cmd = $1
      when /INFO -- : \$\$\$\[end\] (.+)/ =~ line
        r[:exit_results] << $1
      when !r[:rev] && /INFO -- : At revision (\d+)\./ =~ line
        r[:rev] = $1
      when !r[:rev] && /INFO -- : Updated to revision (\d+)\./ =~ line
        r[:rev] = $1
      # INFO -- : 17057 tests, 4935260 assertions, 0 failures, 0 errors, 76 skips
      when /test-all/ =~ cmd && /INFO -- : (\d+ tests?, \d+ assertions?, \d+ failures?, \d+ errors?, \d+ skips?)/ =~ line
        r[:test_all] = $1
      when /test-all/ =~ cmd && /INFO -- (:   \d+\))/ =~ line
        test_all_logging_lines = 2
        r[:test_all_log] << $1
      when /test-all/ =~ cmd && test_all_logging_lines > 0 && /INFO -- (: .+)/ =~ line
        test_all_logging_lines -= 1
        r[:test_all_log] << $1
      # INFO -- : 3568 files, 26383 examples, 200847 expectations, 0 failures, 0 errors, 0 tagged
      when /spec/ =~ cmd && /INFO -- : (\d+ files?, \d+ examples?, \d+ expectations?, \d+ failures?, \d+ errors?, \d+ tagged)/ =~ line 
        r[:test_spec] = $1
      end
    }
  } if File.exist?(logfile)
  r
end

def build_report target
  init_loop_dur = (ENV['BR_LOOP_MINIMUM_DURATION'] || (60 * 2)).to_i # 2 min for default
  build_timeout = (ENV['BR_BUILD_TIMEOUT'] || 2 * 60 * 60).to_i      # 2 hours for default
  alert_to      = (ENV['BR_ALERT_TO'] || '')                         # use default
  report_host   = (ENV['BR_REPORT_HOST'] || 'ci.rvm.jp')             # report host
  if /(.+):(\d+)\z/ =~ report_host
    report_host = $1
    report_port = $2.to_i
  else
    report_port = 80
  end

  state_db = YAML::Store.new(File.join(WORKING_DIR, 'state.yaml'))
  state = nil
  state_db.transaction do
    state = state_db[target] || {loop_dur: init_loop_dur, failure: 0}
  end

  start = Time.now
  result, logfile = build target, result_collector: results = [], build_timeout: build_timeout
  puts result

  # check log file
  r = check_logfile(logfile)
  result = "#{result} (r#{r[:rev]})" if r[:rev]
  results.unshift(*[
    "rev: #{r[:rev]}",
    "test-all : #{r[:test_all]}",
    *r[:test_all_log],
    "test-spec: #{r[:test_spec]}",
    "exit statuses:",
    *r[:exit_results].map{|line| '  ' + line},
    '',
  ].join("\n"))

  # send result
  gist_url = `gist #{logfile}`
  h = {
    name: "#{target}@#{Socket.gethostname}",
    result: result,
    detail_link: gist_url,
    desc: results.join,
    memo: `uname -a`,
    timeout: Integer(build_timeout * 1.5),
    to: alert_to,
  }

  begin
    net = Net::HTTP.new(report_host, report_port)
    p net.put('/results', URI.encode_www_form(h))
  rescue SocketError, Net::ReadTimeout => e
    p e
  end

  # cleanup
  if /OK/ =~ result
    state[:loop_dur] = init_loop_dur
    state[:failure] = 0
  else
    clean_all target if state[:failure] > 0
    state[:failure]  += 1
    state[:loop_dur] += 60 if state[:loop_dur] < 60 * 60 * 3 # 1 hour
  end

  # store last state.
  state_db.transaction do
    state_db[target] = state
  end

  sleep_time = state[:loop_dur] - (Time.now.to_i - start.to_i)
  if sleep_time > 0
    puts "sleep: #{sleep_time}"
    sleep sleep_time
  end
end

def run target
  raise "run is unsupported yet"
end

case cmd
when nil, '-h', '--help'
  puts <<EOS
br.rb: supported commands
  * list
  * build [target]
  * build_all
  * run [target]
  * run_all
EOS

when 'list'
  TARGETS.each{|target, config|
    puts '%-20s - %s' % [target, config]
  }
when 'build'
  result, logfile = build ARGV.shift || raise('build target is not provided')
  unless /OK/ =~ result
    system("#{PAGER} #{logfile}")
  end
when 'build_report'
  build_report ARGV.shift || raise('build target is not provided')
when 'build_all'
  pattern = ARGV.shift if ARGV[0] && ARGV[0] !~ /--/
  TARGETS.each{|target, config|
    next if pattern && Regexp.compile(pattern) !~ target
    build target
  }
when 'run'
  run ARGV.shift
when 'run_all'
  TARGETS.each{|target, config|
    run target
  }
else
  raise "#{cmd} is not supported"
end
