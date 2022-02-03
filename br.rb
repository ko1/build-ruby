require 'optparse'
require 'net/http'
require 'uri'
require 'etc'
require 'socket'
require 'yaml'
require 'yaml/store'
require 'json'
require 'logger'
require 'benchmark'
require 'fileutils'

require_relative 'load_env'

cmd = ARGV.shift

def (DummyCollector = Object.new).<<(obj)
  # ignore
end

class LogCollector
  def initialize rs
    @rs = rs
  end

  def write(line)
    @rs << line.sub(/^E.+ ERROR -- : /, '')
  end

  def close; end
end

def collect_logger rs
  Logger.new(LogCollector.new(rs))
end

def build target_name, extra_opts: ARGV,
          result_collector: DummyCollector,
          build_timeout: (60 * 60 * 2) # 2 hours
  opts = []
  # opts by default
  opts << "--target_name=#{target_name}"
  logfile = File.join(CONFIG_DIR, 'logs', "brlog.#{target_name}.#{Time.now.strftime('%Y%m%d-%H%M%S')}")
  opts << "--logfile=#{logfile}"
  opts << "--root_dir=#{WORKING_DIR}"
  opts << "--timeout=#{build_timeout}"

  # opts from config file
  opts.concat(TARGETS[target_name].arg.split(/\n/))

  # opts from command line
  opts.concat extra_opts

  begin
    Timeout.timeout(build_timeout * 10) do
      # safety guard: build-ruby.rb's timeout may not work https://ruby.slack.com/archives/C8Q2X0NSZ/p1609806757225800
      IO.popen("ruby #{BUILD_RUBY_SCRIPT} #{opts.join(' ')}", 'r', err: [:child, :out]){|io|
        while line = io.gets
          result_collector << line
          puts line
        end
      }
    end
  rescue SystemCallError => e
    line = "br.rb: #{e.inspect}"
    result_collector << line
    puts line
  rescue Timeout::Error => e
    STDERR.puts e
    result_collector << "$$$ #{$!.inspect}"
    result_collector << "### enter analyzing mode for stuck processes (br.rb)"
    require_relative 'psj'
    kill_descendant_with_gdb_info collect_logger(result_collector)
  end

  result = if $?.success?
             'OK'
           else
             'NG'
           end
  # pp result_collector
  [result, logfile]
end

def clean_all target
  build target, extra_opts: ['--rm=all', "--root_dir=#{WORKING_DIR}"]
end

def check_logfile logfile
  r = {
    exit_results: [],
    rev: nil,
    test_all: nil,
    test_spec: nil,
  }

  cmd = nil
  test_all_logging_lines = 0

  open(logfile){|f|
    f.each_line.with_index{|line, lineno|
      line.scrub!
      case
      when /ERROR -- : (.+)/ =~ line
        r[:exit_results] << [lineno, "stderr: " + $1]
      when /INFO -- : \$\$\$\[beg\] (.+)/ =~ line
        r[:exit_results] << [lineno, cmd = $1]
      when /INFO -- : \$\$\$\[end\] (.+)/ =~ line
        cmd.replace($1)
      when !r[:rev] && /INFO -- : At revision (\d+)\./ =~ line
        r[:rev] = "r#{$1}"
      when !r[:rev] && /INFO -- : Updated to revision (\d+)\./ =~ line
        r[:rev] = "r#{$1}"
      # INFO -- : 17057 tests, 4935260 assertions, 0 failures, 0 errors, 76 skips
      when !r[:rev] && /INFO -- : Latest commit hash = (.+)/ =~ line
        r[:rev] = $1
      when /test-all/ =~ cmd && /INFO -- : (\d+ tests?, \d+ assertions?, \d+ failures?, \d+ errors?, \d+ skips?)/ =~ line
        r[:test_all] = $1
      # INFO -- : 3568 files, 26383 examples, 200847 expectations, 0 failures, 0 errors, 0 tagged
      when /spec/ =~ cmd && /INFO -- : (\d+ files?, \d+ examples?, \d+ expectations?, \d+ failures?, \d+ errors?, \d+ tagged)/ =~ line 
        r[:test_spec] = $1
      end
    }
  } if File.exist?(logfile)
  r
end


CORE_DIR = '/tmp/cores'
CORE_COLLECT_DIR = "/tmp/collected_cores"

def setup_collect_cores
  unless File.exist?(CORE_DIR)
    FileUtils.mkdir(CORE_DIR)
    FileUtils.chmod(0777, CORE_DIR)
  end

  Dir.glob(File.join(CORE_DIR, "core.#{Process.uid}.*")) do |core|
    FileUtils.rm(core, force: true)
  end

  # collect all cores
  Process.setrlimit Process::RLIMIT_CORE, -1
end

def collect_cores logfile
  dst_dir = "#{CORE_COLLECT_DIR}/#{Time.now.to_i}"
  FileUtils.mkdir_p(dst_dir)

  cores = Dir.glob(File.join(CORE_DIR, "core.#{Process.uid}.*")).map do |core|
    # readelf -n core.5.30119 | egrep '\s+/' | sort | uniq
    related_files = `readelf -n #{core}`.each_line.map{|line|
      if /^\s+(\/.+)$/ =~ line && !$1.start_with?('/usr')
        $1
      end
    }.compact.uniq
    exec = nil
    related_files.each{|file|
      dst = File.join(dst_dir, file)
      FileUtils.mkdir_p(File.dirname(dst))
      FileUtils.cp file, dst
      exec = file if /ruby$/ =~ file # maybe ...
    }

    if exec
      # cmd = "gdb -batch -se #{exec} -c #{core} -ex 'info th' -ex 'thread apply all bt'"
      cmd = "gdb -batch -se #{exec} -c #{core} -x gdbscript"
      open(logfile, 'a'){|f| f.puts "\n$ #{cmd}"}
      system("#{cmd} >> #{logfile}")
    end

    FileUtils.mv core, dst_dir
    core
  end

  unless cores.empty?
    # clean older archives
    Dir.glob(File.join(CORE_COLLECT_DIR, '*.tar.gz')) do |archive|
      if File.mtime(archive) < Time.now - (60 * 60 * 24 * 7) # 7 days
        FileUtils.rm(archive, force: true, verbose: true)
      end
    end

    archive = "#{dst_dir}.tar.gz"
    system("tar acf #{archive} -C #{File.dirname(dst_dir)} #{File.basename(dst_dir)}")
    FileUtils.rm_rf dst_dir
    archive
  end
end

UNAME_A = `uname -a`

def build_report target_name
  setup_collect_cores

  target = TARGETS[target_name]

  if /(.+):(\d+)\z/ =~ target.report_host
    report_host = $1
    report_port = $2.to_i
  else
    report_host = target.report_host
    report_port = 80
  end

  state_db = YAML::Store.new(File.join(CONFIG_DIR, 'state.yaml'))
  state = nil
  state_db.transaction do
    state = state_db[target_name] || {
      loop_dur: target.loop_minimum_duration,
      failure: 0,
      total_success: 0,
      total_failure: 0,
    }
  end

  result, out_log, logfile = nil
  tm = Benchmark.measure{
    result, logfile = build target_name, result_collector: out_log = [], build_timeout: target.build_timeout
  }

  # check log file
  r = check_logfile(logfile)

  # check core files
  core_archive = collect_cores logfile

  # send result

  h = {
    name: "#{target_name}@#{Socket.gethostname}",
    rev: r[:rev],
    result: result,
    desc: out_log.join,
    desc_json: JSON.dump(r),
    memo: UNAME_A,
    elapsed_time: tm.real,
    core_link: (core_archive && open(core_archive, 'rb')),
    timeout: Integer(target.build_timeout * 1.5),
    to: target.alert_to,

    # logfile
    detail_link: File.basename(logfile),
    details: open(logfile).read,
  }

  begin
    if false
      http = Net::HTTP.new(report_host, report_port)
      p http.put('/results', URI.encode_www_form(h))
    else
      data = h.map{|k, v| [k.to_s, (v.respond_to?(:read) ? v : v.to_s)] if v}.compact
      req = Net::HTTP::Put.new('/results')
      req.set_form(data, 'multipart/form-data')
      Net::HTTP.new(report_host, report_port).start do |http|
        p http.request(req)
      end
    end
  rescue SocketError, Net::ReadTimeout => e
    p e
  ensure
    FileUtils.rm_f core_archive if core_archive
  end

  # cleanup
  if /OK/ =~ result
    state[:loop_dur] = target.loop_minimum_duration
    state[:failure] = 0
    state[:total_success] = 0 unless state.has_key? :total_success
    state[:total_success] += 1
  else
    clean_all target_name if state[:failure] >= 1000
    state[:failure]  += 1
    state[:loop_dur] = (state[:loop_dur] * 1.2).to_i if state[:loop_dur] < 60 * 60 * 3 # 1 hour
    state[:total_failure] = 0 unless state.has_key? :total_failure
    state[:total_failure] += 1
  end

  # store last state.
  state_db.transaction do
    state_db[target_name] = state
  end

  sleep_time = state[:loop_dur] - tm.real.to_i

  if target.loop_minimum_duration != 0
    # introduce randomness
    sleep_time += 60 - rand(120)
  end

  if sleep_time > 0
    puts "sleep: #{sleep_time}"
    sleep sleep_time
  end
end

def run target_name
  raise "run is unsupported yet"
end

def exe target_name
  build target_name, extra_opts: ['--only-show=exe', *ARGV]
end

case cmd
when nil, '-h', '--help'
  puts <<EOS
br.rb: supported commands
  * list
  * build [target_name]
  * build_all
  * run [target_name]
  * run_all
EOS

when 'list'
  TARGETS.each{|target_name, config|
    puts '%-20s - %s' % [target_name, config.arg]
  }
when 'build'
  result, logfile = build ARGV.shift || raise('build target is not provided')
  unless /OK/ =~ result
    system("#{PAGER} #{logfile}") unless PAGER.empty?
  end
when 'build_report'
  build_report ARGV.shift || raise('build target is not provided')
when 'build_all'
  pattern = ARGV.shift if ARGV[0] && ARGV[0] !~ /--/
  TARGETS.each{|target_name, config|
    next if pattern && Regexp.compile(pattern) !~ target_name
    build target_name
  }
when 'run'
  run ARGV.shift
when 'exe'
  exe ARGV.shift
when 'run_all'
  TARGETS.each{|target_name, config|
    run target_name
  }
when 'check_logfile'
  text = JSON.dump(check_logfile(ARGV.shift))
  puts text
when 'update_default_targets'
  branches = `svn ls https://svn.ruby-lang.org/repos/ruby/branches`.each_line.map{|line|
    [$1, "https://svn.ruby-lang.org/repos/ruby/branches/#{$1}"] if /^(ruby_.+)\// =~ line
  }.compact
  tags = `svn ls https://svn.ruby-lang.org/repos/ruby/tags`.each_line.map{|line|
    [$1, "https://svn.ruby-lang.org/repos/ruby/tags/#{$1}"] if /^(v.+)\// =~ line
  }.compact
  open(File.join(__dir__, 'default_targets.yaml'), 'w'){|f|
    f.puts "trunk:"
    branches.each{|n, u|
      f.puts "#{n}: #{u}"
    }
    tags.each{|n, u|
      f.puts "#{n}: #{u}"
    }
  }
  puts "update: #{branches.size} branches, #{tags.size} tags"
else
  raise "#{cmd} is not supported"
end
