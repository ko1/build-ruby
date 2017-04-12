
require 'optparse'

cmd = ARGV.shift

WORKING_DIR = File.expand_path(ENV['BUILD_RUBY_WORKING_DIR'] || "~/ruby")
BUILD_RUBY_SCRIPT = File.join(File.dirname(__FILE__), 'build-ruby.rb')
PAGER = ENV['PAGER'] || 'less'
BR_MINIMUM_DURATION = [ENV['BR_MINIMUM_DURATION'].to_i, (60 * 3)].max

def (DummyOutCollector = Object.new).<<(obj)
  # ignore
end

def build target, out_collector = DummyOutCollector
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
  opts << ARGV

  IO.popen("ruby #{BUILD_RUBY_SCRIPT} #{opts.join(' ')}"){|io|
    while line = io.gets
      out_collector << line
      puts line
    end
  }
  [$?, logfile]
end

def build_loop target
  loop{
    start = Time.now
    _r, _logfile = build target, results = []
    p _r
    # send result
    # TODO

    # 60 sec break
    sleep_time = BR_MINIMUM_DURATION - (Time.now.to_i - start.to_i)
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
