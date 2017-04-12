require 'sinatra'
require 'yaml/store'

# load db
MEM_DB = Hash.new{|h, k| h[k] = []}
Dir.glob(File.join(__dir__, 'db', '*')){|db_file|
  data = []
  db = YAML::Store.new(db_file)
  db.transaction{
    db.roots.each{|k|
      data << [k, db[k]]
    }
  }
  MEM_DB[File.basename(db_file)] = data
}

def db_file name
  File.join('db', name)
end

def db_write name, **opts
  raise "unsupported name: #{name}" if !name || name.empty? || /[^A-z0-9\-@]/ =~ name
  now = Time.now.to_i
  MEM_DB[name] << [now, opts]
  db = YAML::Store.new(db_file(name))
  db.transaction{
    db[now] = opts
  }
  alert name, opts[:result], otps2msg(name, opts) if opts[:result] != 'OK'
end

def db_last_update name
  File.mtime(db_file(name))
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
  db_write(name, **opts)
  alert_setup(name, par:timeout)
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
ALERT_TO = %w(ko1c-failure@atdot.net)

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
  cmd = "mail -s 'failure alert on #{name} (#{result})' #{ALERT_TO.join(' ')}"
  logger.info cmd
  IO.popen(cmd, 'r+'){|io|
    io.puts msg
    io.close_write
    puts io.read
  }
end

def alert_setup name, timeout_str
  timeout = (timeout_str || (60 * 60 * 3)).to_i
  WATCH_LIST[name] = {timeout: timeout, alerted: false}
end

# timeout alert
Thread.abort_on_exception = true

WATCH_LIST = {
  # name => {timeout: sec, alerted: ...}
}

Thread.new{
  loop{
    WATCH_LIST.each{|name, cfg|
      sec = Time.now.to_i - db_last_update(name).to_i
      if sec > cfg[:timeout]
        if cfg[:alerted]
          if sec > cfg[:alerted]
            alert name 'timeout (continue)', "No response from #{name} (#{sec} sec)"
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
