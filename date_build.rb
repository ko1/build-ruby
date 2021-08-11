
require 'optparse'
require 'date'

config = {
  mode: :build,
  iter: :m,
  until: Date.today,
}

opts = OptionParser.new do |o|
  o.on('-m MODE', '--mode=MODE', 'build|run'){|mode|
    case mode
    when 'exe', 'build'
      config[:mode] = mode.to_sym
    else
      raise "Unknown mode: #{mode}"
    end
  }
  o.on('--since=DATE'){|date|
    config[:since] = Date.parse(date)
  }
  o.on('--until=DATE'){|date|
    config[:until] = Date.parse(date)
  }
  o.on('-i ITER', '--iter=ITER', 'm[onthly]|w[eekly]|d[aily]'){|m|
    config[:iter] = m[0].downcase.to_sym
  }
  o.on('-q'){
    config[:quiet] = true
  }
end

opts.parse!(ARGV)

def default_since_date mode
  t = Date.today.prev_year

  case mode
  when :y, :m
    t = Date.new(t.year, t.month, 1)
  end
  t
end

target = ARGV.shift || 'trunk'
t = config[:since] || default_since_date(config[:iter])
warnned = false

while t < config[:until]
  cmd = "ruby br.rb #{config[:mode]} #{target} --date=#{t.strftime("%Y/%m/%d")} #{ARGV.join(' ')}"
  puts "$ #{cmd}" unless config[:quiet]

  case ENV['NOOP']
  when '0'
    system(cmd)
  when '1'
    # ignore
  else
    unless warnned
      warn "# To execute the command, specify NOOP=0 envval"
      warnned = true
    end
  end

  case config[:iter]
  when :y
    t = t.next_year
  when :m
    t = t.next_month
  when :d
    t = t.next_day
  else
    raise "Unknown iter: #{config[:iter].inspect}"
  end
end

