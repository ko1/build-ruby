require 'sinatra'
require 'yaml/store'

# load db
class Entries
  def initialize
    @ary = []
  end

  def <<(e)
    @ary << e
    update
  end

  def limit_time
    Time.now.to_i - (60 * 60 * 24 * 3)
  end

  def update
    limit_tm = limit_time()
    @ary.delete_if{|(t, opts)|
      if t < limit_tm
        true
      else
        break
      end
    }
  end

  def merge(es)
    limit_tm = limit_time()
    es.each{|e|
      if t > limit_tm
        @ary << e
      end
    }
  end

  def each
    @ary.each{|e|
      yield e
    }
  end

  def reverse_each
    @ary.reverse_each{|e|
      yield e
    }
  end

  def last
    @ary.last
  end
end

MEM_DB = Hash.new{|h, k| h[k] = Entries.new}

def db_file_name name
  File.join(__dir__, 'db', name)
end

def db_files
  Dir.glob(File.join(__dir__, 'db', '*')).sort.each{|db_file|
    yield db_file
  }
end

db_files{|db_file|
  data = []
  db = YAML::Store.new(db_file)
  db.transaction{
    db.roots.each{|k|
      data << [k, db[k]]
    }
  }
  MEM_DB[File.basename(db_file)].merge(data)
}

def db_write name, **opts
  p [name, opts[:result]]
  raise "unsupported name: #{name}" if !name || name.empty? || /[^A-z0-9\-@]/ =~ name
  now = Time.now.to_i
  MEM_DB[name] << [now, opts]
  db = YAML::Store.new(db_file_name(name))
  db.transaction{
    db[now] = opts
  }
  alert name, opts[:result], otps2msg(name, opts) if /OK/ !~ opts[:result]
end

def db_last_update name
  File.mtime(db_file_name(name))
end

# utils
def par v
  params[v.to_s]
end

def params_set *set
  set.each_with_object({}){|k, h|
    h[k.to_sym] = params[k.to_s]
  }
end

helpers do
  def h(text)
    Rack::Utils.escape_html(text)
  end
end

# actions
get '/' do
  erb :results
end

get '/status' do
  erb :results
end

put '/results' do
  name = par:name
  opts = params_set(:result, :desc, :detail_link, :memo)
  alert_setup(name, par(:timeout), par(:to))
  db_write(name, **opts)
  'OK'
end

get '/results/' do
  erb :results
end

get '/results/:name' do |name|
  erb :results_each_name, locals: {name: name}
end

get '/results/:name/:time' do |name, time|
  erb :results_each_time, locals: {name: name, time: time.to_i}
end

# alert
def otps2msg name, opts
<<EOS
Alert on #{name}
rsult : #{opts[:result]}
detail: #{opts[:detail_link]}
desc:
#{opts[:desc]}
memo:
#{opts[:memo]}
EOS
end

def alert name, result, msg
  to = WATCH_LIST.dig(name, :to) || []
  to = %w(ruby-alerts@quickml.atdot.net) if to.empty?
  cmd = "mail -s 'failure alert on #{name} (#{result})' -aFrom:ko1c-failure@atdot.net #{to.join(' ')}"
  puts cmd
  IO.popen(cmd, 'r+'){|io|
    io.puts msg + "\n\n-- \nhttp://ci.rvm.jp/"
    io.close_write
    puts io.read
  }
end

def alert_setup name, timeout_str, to
  timeout = (timeout_str || (60 * 60 * 3)).to_i
  to = to.split(/[, ]+/) if to

  WATCH_LIST[name] = {timeout: timeout, alerted: false, to: to}
end

# timeout alert
Thread.abort_on_exception = true

WATCH_LIST = {
  # name => {timeout: sec, alerted: ...,
  #          to: [...]}
}

helpers do
  def recent_stat vs, sec
    fs = []
    rs_count = 0
    until_tm = Time.at(Time.now.to_i - sec).to_i
    vs.reverse_each{|e|
      t, opts = *e
      if t >= until_tm
	rs_count += 1
	fs << e if /OK/ !~ opts[:result]
      else
	break
      end
    }
    return fs, rs_count
  end
end

Thread.new{
  loop{
    WATCH_LIST.each{|name, cfg|
      sec = Time.now.to_i - db_last_update(name).to_i
      if sec > cfg[:timeout]
        if cfg[:alerted]
          if Time.now.to_i > cfg[:alerted]
            alert name, 'timeout (continue)', "No response from #{name} (#{sec} sec)"
            cfg[:alerted] = Time.now.to_i + (60 * 60) # next alert is 1 hour later
          end
        else
          alert name, 'timeout', "No response from #{name} (#{sec} sec)"
          cfg[:alerted] = Time.now.to_i + (60 * 60) # next alert is 1 hour later
        end
      else
        cfg[:alerted] = false
      end
    }
    sleep 60
  }
}
