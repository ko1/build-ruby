require 'bundler'
Bundler.require

Time.zone = "Tokyo"
ActiveRecord::Base.default_timezone = :local

class ResultServer < Sinatra::Base
  configure do
    register Sinatra::ActiveRecordExtension
    set :database, adapter: "sqlite3", database: File.expand_path("~/tmp/result_srv.db")
  end

  # actions
  get '/' do
    @test_status = TestStatus.all
    erb :results
  end

  def par v
    params[v.to_s]
  end

  def params_set *set
    set.each_with_object({}){|k, h|
      h[k.to_sym] = params[k.to_s]
    }
  end

  def db_write name, **opts
    p [name, opts[:result]]
    r = Result.new(name: name, **opts)
    r.save
    alert_setup(name, opts[:timeout], opts[:to])
    alert name, opts[:result], otps2msg(name, opts), r.id if /OK/ !~ opts[:result]
    r.id
  end

  put '/results' do
    name = par:name
    opts = params_set(:result, :desc, :detail_link, :memo)
    result_id = db_write(name, **opts)
    "http://ci.rvm.jp/results/#{name}/#{result_id}"
  end

  get '/results/' do
    @test_status = TestStatus.where(visible: true)
    erb :results
  end

  def results_name name
    tm = Time.at(Time.now - 3 * 60 * 60 * 24)
    results = Result.where(name: name).where('updated_at > ?', tm).order(updated_at: :desc)
    erb :results_each_name, locals: {name: name, results: results}
  end

  get '/results/:name' do |name|
    results_name name
  end

  get '/results/:name/' do |name|
    results_name name
  end
  
  get '/results/:name/:result_id' do |name, result_id|
    begin
      result = Result.find(result_id)
      erb :results_each_time, locals: {name: name, result: result}
    rescue ActiveRecord::RecordNotFound
      'not found'
    end
  end

  helpers do
    def h(text)
      Rack::Utils.escape_html(text)
    end

    def recent_failures_stat name, days
      tm = Time.at(Time.now - days * 60 * 60 * 24)
      if name
        total = Result.where(name: name).where("updated_at > ?", tm).count
        fails = Result.where(name: name).where("updated_at > ?", tm).where("result NOT LIKE ?", "OK%").count
      else
        total = Result.where("updated_at > ?", tm).count
        fails = Result.where("updated_at > ?", tm).where("result NOT LIKE ?", "OK%").count
      end
      if total > 0
        "#{'%4d' % fails} / #{'%4d' % total} (#{'%4.1f%%' % (100.0 * fails / total)})"
      else
        "N/A"
      end
    end

    def recent_failures name, days
      tm = Time.at(Time.now - days * 60 * 60 * 24)
      Result.where(name: name).where("updated_at > ?", tm).where("result NOT LIKE ?", "OK%").order(:updated_at, :desc).limit(5)
    end

    def good_diff(t)
      d = Time.now - t
      case
      when d < 60
        "#{'%02d' % d} sec"
      when d < 60 * 60
        "#{'%02d' % (d/60)} min"
      else
        "#{Integer(d/(60 * 60))} hour"
      end
    end
  end
end

class Result < ActiveRecord::Base
  after_commit :update_test_status

  private
  def update_test_status
    TestStatus.update_latest(self)
  end
end

class TestStatus < ActiveRecord::Base
  belongs_to :result

  def self.update_latest(result)
    if test = self.where(name: result.name).first
      test.update(result: result)
      test.save
    else
      test = TestStatus.new(name: result.name, visible: true, result: result)
      test.save
    end
  end
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

def alert name, result, msg, result_id = nil
  to = WATCH_LIST.dig(name, :to) || []
  to = %w(ruby-alerts@quickml.atdot.net) if to.empty?
  subject = "failure alert on #{name} (#{result})"
  url = "http://ci.rvm.jp/results/#{name}/#{result_id}"
  cmd = "mail -s '#{subject}' -aFrom:ko1c-failure@atdot.net #{to.join(' ')}"

  if ENV['RACK_ENV'] == 'test'
    $last_alert = {
      to: to,
      subject: subject,
      url: url,
      cmd: cmd,
      msg: msg,
    }
  else
    puts cmd
    IO.popen(cmd, 'r+'){|io|
      io.puts msg + "\n\n-- \n{url}"
      io.close_write
      puts io.read
    }
    system("ruby slack-notice.rb '<!here> #{subject}. See #{url}'")
  end
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

if $0 == __FILE__
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
end
