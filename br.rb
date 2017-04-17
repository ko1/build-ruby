
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
        line = "br.rb: Process.kill(:KILL, -#{io.pid})"
        result_collector << line
        puts line
        Process.kill(:KILL, -io.pid) # kill process group
        sleep 1
      end
    }
  rescue SystemCallError => e
    line = "br.rb: #{e.inspect}"
    result_collector << line
    puts line
  end
  [$?, logfile]
end

def clean_all target
  build target, extra_opts: ['--rm=all']
end

def build_loop target
  loop_dur      = (ENV['BR_LOOP_MINIMUM_DURATION'] || (60 * 3)).to_i # 180 sec for default
  build_timeout = (ENV['BR_BUILD_TIMEOUT'] || 3 * 60 * 60).to_i      # 3 hours for default
  alert_to      = (ENV['BR_ALERT_TO'] || '')                         # use default

  loop{
    start = Time.now
    r, logfile = build target, result_collector: results = [], build_timeout: build_timeout
    p r
    # send result
    gist_url = r.success? ? nil : `gist #{logfile}`
    h = {
      name: "#{target}@#{Socket.gethostname}",
      result: r.success? ? 'OK' : 'NG',
      detail_link: gist_url,
      desc: results.join,
      memo: Etc.uname.inspect,
      timeout: build_timeout,
      to: alert_to,
    }
    begin
      net = Net::HTTP.new('ci.rvm.jp', 80)
      p net.put('/results', URI.encode_www_form(h))
    rescue SocketError => e
      p e
    end

    # cleanup all
    unless r.success?
      clean_all target
    end

    # 60 sec break
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
