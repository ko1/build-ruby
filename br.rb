
require 'optparse'
require 'timeout'
require 'net/http'
require 'uri'
require 'etc'
require 'socket'

cmd = ARGV.shift

WORKING_DIR = File.expand_path(ENV['BUILD_RUBY_WORKING_DIR'] || "~/ruby")
BUILD_RUBY_SCRIPT = File.join(File.dirname(__FILE__), 'build-ruby.rb')
PAGER = ENV['PAGER'] || 'less'

def (DummyCollector = Object.new).<<(obj)
  # ignore
end

def build target, extra_opts: ARGV, result_collector: DummyCollector, build_timeout: (60 * 60 * 3) # 3 hours
  target_file = File.expand_path(File.join(WORKING_DIR, "#{target}.br"))
  opts = []
  # opts by default
  opts << "--target_name=#{target}"
  logfile = File.join(WORKING_DIR, 'logs', "brlog.#{target}.#{Time.now.strftime('%Y%m%d-%H%M%S')}")
  opts << "--logfile=#{logfile}"

  # opts from config file
  opts.concat open(target_file){|f|
    f.readlines.map{|line| line.chomp}
  }

  # opts from command line
  opts.concat extra_opts
  timeout_p = false

  begin
    IO.popen("ruby #{BUILD_RUBY_SCRIPT} #{opts.join(' ')}", 'r', pgroup: 0){|io|
      begin
        Timeout.timeout(build_timeout) do
          while line = io.gets
            result_collector << line
            puts line
          end
        end
      rescue Interrupt, Timeout::Error
        IO.popen('ps t', 'r'){|psio|
          while line = psio.gets
            result_collector << line
            puts line
          end
        }
        line = "$$$ br.rb: Process.kill(:SEGV, -#{io.pid})"
        result_collector << line
        puts line
        Process.kill(:SEGV, -io.pid) # SEGV process group
        timeout_p = true
        sleep 1
        Process.kill(:KILL, -io.pid) # kill process group
        sleep 1
      end
    }
  rescue SystemCallError => e
    line = "br.rb: #{e.inspect}"
    result_collector << line
    puts line
  end

  result = case
    when timeout_p
      'NG/timeout'
    when $?.success?
      result = 'OK'
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
    test_spec: nil,
  }

  cmd = nil
  open(logfile){|f|
    f.each_line{|line|
      case
      when /INFO -- : \$\$\$\[beg\] (.+)/ =~ line
        cmd = $1
      when /INFO -- : \$\$\$\[end\] (.+)/ =~ line
        r[:exit_results] << $1
      when !r[:rev] && /INFO -- : At revision (\d+)\./ =~ line
        r[:rev] = $1
      # I, [2017-05-18T00:26:50.162829 #7889]  INFO -- : 17057 tests, 4935260 assertions, 0 failures, 0 errors, 76 skips
      when /test-all/ =~ cmd     && /INFO -- : (\d+ tests, \d+ assertions, \d+ failures, \d+ errors, \d+ skips)/ =~ line
        r[:test_all] = $1
      # I, [2017-05-18T00:04:51.269280 #10900]  INFO -- : 3568 files, 26383 examples, 200847 expectations, 0 failures, 0 errors, 0 tagged
      when /spec/ =~ cmd && /INFO -- : (\d+ files, \d+ examples, \d+ expectations, \d+ failures, \d+ errors, \d+ tagged)/ =~ line 
        r[:test_spec] = $1
      end
    }
  } if File.exist?(logfile)
  r
end

def build_loop target
  init_loop_dur = (ENV['BR_LOOP_MINIMUM_DURATION'] || (60 * 2)).to_i # 2 min for default
  build_timeout = (ENV['BR_BUILD_TIMEOUT'] || 3 * 60 * 60).to_i      # 3 hours for default
  alert_to      = (ENV['BR_ALERT_TO'] || '')                         # use default

  loop_dur = init_loop_dur

  loop{
    start = Time.now
    result, logfile = build target, result_collector: results = [], build_timeout: build_timeout

    puts result

    # check log file
    r = check_logfile(logfile)
    result = "#{result} (r#{r[:rev]})" if r[:rev]
    results.unshift(
      "rev: #{r[:rev]}\n",
      "test-all : #{r[:test_all]}\n",
      "test-spec: #{r[:test_spec]}\n",
      "exit statuses: \n",
      *r[:exit_results].map{|line| '  ' + line + "\n"})

    # send result
    gist_url = `gist #{logfile}`
    h = {
      name: "#{target}@#{Socket.gethostname}",
      result: result,
      detail_link: gist_url,
      desc: results.join,
      memo: `uname -a`,
      timeout: build_timeout,
      to: alert_to,
    }

    begin
      net = Net::HTTP.new('ci.rvm.jp', 80)
      p net.put('/results', URI.encode_www_form(h))
    rescue SocketError, Net::ReadTimeout => e
      p e
    end

    # cleanup all
    if /OK/ =~ result
      loop_dur = init_loop_dur
    else
      clean_all target
      loop_dur += 60 if loop_dur < 60 * 60 # 1 hour
    end

    sleep_time = loop_dur - (Time.now.to_i - start.to_i)
    if sleep_time > 0
      puts "sleep: #{sleep_time}"
      sleep sleep_time
    end
  }
end

def target_configs
  Dir.glob(File.join(WORKING_DIR, '*.br')){|file|
    yield file
  }
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
  target_configs{|target_config|
    puts File.basename(target_config, '.br')
  }
when 'build'
  r, logfile = build ARGV.shift || raise('build target is not provided')
  unless r.success?
    system("#{PAGER} #{logfile}")
  end
when 'build_loop'
  build_loop ARGV.shift || raise('build target is not provided')
when 'build_all'
  pattern = ARGV.shift if ARGV[0] && ARGV[0] !~ /--/
  target_configs{|target_config|
    next if pattern && Regexp.compile(pattern) !~ target_config
    build File.basename(target_config, '.br')
  }
when 'run'
  run ARGV.shift
when 'run_all'
  target_configs{|target_config|
    run File.basename(target_config, '.br')
  }
else
  raise "#{cmd} is not supported"
end
