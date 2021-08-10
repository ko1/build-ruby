
require 'optparse'
require 'date'

config = {
  mode: :m,
  until: Date.today
}

opts = OptionParser.new do |o|
  o.on('--since=DATE'){|date|
    config[:since] = Date.parse(date)
  }
  o.on('--until=DATE'){|date|
    config[:until] = Date.parse(date)
  }
  o.on('--mode=MODE', 'm[onthly]|w[eekly]|d[aily]'){|m|
    config[:mode] = m[0].downcase.to_sym
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
t = config[:since] || default_since_date(config[:mode])
warnned = false

while t < config[:until]
  cmd = "ruby br.rb build #{target} --only-install --date=#{t.strftime("%Y/%m/%d")}"
  puts "$ #{cmd}"

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

  case config[:mode]
  when :y
    t = t.next_year
  when :m
    t = t.next_month
  when :d
    t = t.next_day
  else
    raise "#{config[:m].inspect}"
  end
end

