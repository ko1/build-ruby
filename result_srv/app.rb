
require 'bundler'
Bundler.require

require 'json'
require 'net/http'
require 'uri'
require 'cgi/util'
require 'zlib'
require 'pp'
require "sinatra/reloader" if development?

# Time.zone = "Tokyo"

if defined? ActiveRecord.default_timezone
  ActiveRecord.default_timezone = :local
else
  ActiveRecord::Base.default_timezone = :local
end

class ResultServer < Sinatra::Base
  configure do
    register Sinatra::ActiveRecordExtension
    set :database, adapter: "sqlite3", database: File.expand_path("~/tmp/result_srv.db")
  end

  configure :development do
    register Sinatra::Reloader
  end

  get '/check' do
    'OK'
  end

  # actions
  get '/' do
    @test_status = TestStatus.index_all_latest
    erb :index
  end

  get '/all' do
    @test_status = TestStatus.order(:name)
    erb :index
  end

  def query_period days = 3
    days = params['d']&.to_i || days

    #                    start
    # --ta---------------tb---------> time
    #    <===  days  ====>
    tb_sec = params['start']&.to_i || Time.now.to_i
    ta = Time.at(tb_sec - days * 60 * 60 * 24)
    tb = Time.at(tb_sec)
    return days, ta, tb
  end

  get '/results' do
    redirect to '/latest_results'
  end

  get '/results/' do
    redirect to '/latest_results'
  end

  get '/latest_results' do
    days, ta, tb = query_period(1)

    results = Result
      .where('updated_at > ? and updated_at <= ?', ta, tb)
      .order(updated_at: :desc)

    erb :results, locals: {title: 'Recent results', results: results, days: days, ta: ta, tb: tb, name: nil}
  end

  get '/failure_results' do
    days, ta, tb = query_period

    results = Result
      .where('updated_at > ? and updated_at <= ?', ta, tb)
      .where('result like "%NG%"')
      .order(updated_at: :desc)

    erb :results, locals: {title: 'Recent failure results', results: results, days: days, ta: ta, tb: tb, name: nil}
  end

  get '/results/:name' do |name|
    days, ta, tb = query_period

    results = Result
      .where(name: name)
      .where('updated_at > ? and updated_at <= ?', ta, tb)
      .order(updated_at: :desc)
      erb :results, locals: {title: "Recent results of #{name}", name: name, results: results, days: days, ta: ta, tb: tb}
  end

  get '/results/:name/' do |name|
    redirect to("/results/#{name}")
  end

  get '/results/:name/:result_id' do |name, result_id|
    begin
      result = Result.find(result_id)
      erb :result, locals: {name: name, result: result}
    rescue ActiveRecord::RecordNotFound
      'not found'
    end
  end

  def log_data name
    File.read("logfiles/#{name}")
  rescue
    Zlib::GzipReader.open("logfiles/#{name}.gz"){|gz| gz.read}
  end

  get '/logfiles/:name' do
    name = params['name']
    #content_type 'text/plain'
    begin
      data = log_data(name)

      @name = name
      @data = []

      data.each_line.with_index{|line, ln|
        link = "L#{ln}"
        if /T([\d:]+)\..+\s(INFO|ERROR) -- : (.*)$/ =~ line
          time, info = CGI.escapeHTML($1), CGI.escapeHTML($3)
          error_prefix = '<span class="stderr_prefix"></span>' if $2 == 'ERROR'
          @data << "<a class='lines' alt='#{time}' id='#{link}' href='\##{link}'></a>#{error_prefix}#{info}"
        end
      }
      erb :logfile
    rescue => e
      CGI.escapeHTML("#{e}")
    end
  end

  get '/logfiles_/:name' do
    name = params['name']
    content_type 'text/plain'
    begin
      log_data(name)
    rescue
      'not found...'
    end
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
    # p [name, opts[:result]]
    r = Result.new(name: name, **opts)
    r.save
    alert_setup(name, opts[:timeout], opts[:to])
    alert(name, opts[:result], opts[:rev], otps2msg(name, opts), r.id) unless r.success?
    r.id
  end

  put '/results' do
    name = par:name

    # receive
    opts = params_set(:result, :desc, :desc_json, :rev, :elapsed_time, :detail_link, :memo, :details)

    # write to file
    details = opts.delete(:details)
    logname = opts.delete(:detail_link)

    if details && logname
      Zlib::GzipWriter.open("logfiles/#{logname}.gz"){|f|
        f.write details
      }
      opts[:detail_link] = "/logfiles/#{logname}"
    else
      p name: name, details: details, logname: logname
    end

    # write to DB
    result_id = db_write(name, **opts)

    "http://ci.rvm.jp/results/#{name}/#{result_id}"
  end

  helpers do
    if development?
      def style
        File.read('views/style.css')
      end
    else
      STYLE = File.read('views/style.css')
      def style
        STYLE
      end
    end

    def banner result = nil
      if result
        "<div><a href='/'>top</a> / #{link_to_name_of result}</div>"
      else
        "<div><a href='/'>top</a>"
      end
    end

    def h(text)
      Rack::Utils.escape_html(text)
    end

    def link_to_log_of result
      if result.detail_link
        "<a href='#{result.detail_link}'>[LOG]</a>"
      end
    end

    def link_to_name_of result
      name = h(result.name)
      "<a href='/results/#{name}'>#{name}</a>"
    end

    def link_to result
      name = h(result.name)
      "<a href='/results/#{name}/#{result.id}'>#{result.updated_at}</a>"
    end

    def rev_link result
      if rev = result.rev
        "<a href='https://github.com/ruby/ruby/commit/#{h(rev)}'>#{h(rev)}</a>"
      end
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

    # <a href=<%= "#{log_link}\#L#{lineno}" || '' %> class='lineno'>L<%= lineno.to_i %></a>	<%= emph_error() %>
    def exit_results_line log_link, lineno, line
      line = line.split("\r").first # TODO: to be deleted
      case line
      when /^stderr: (.+)/
        line_class = '<span class="stderr_line">'
        line = $1
      when /exit with 0\./
        line_class = '<span class="success_line">'
      when /exit with \d+\./
        line_class = '<span class="failed_line">'
      end
      link = "href='#{log_link}\#L#{lineno}' " if log_link
      "<tr><td align='right'><a #{link}class='lines' alt='#{lineno}'></a></td><td>#{line_class}#{h(line)}</span></td></tr>"
    end

    def each_name_navi last_result, days
      if last_result
        "<a href='?start=#{last_result.updated_at.to_i}&d=#{days}'>previous #{days} days</a>"
      end
    end
  end
end

class Result < ActiveRecord::Base
  after_commit :update_test_status

  def success?
    /OK/ =~ self.result
  end

  def pretty_elapsed_time
    if t = self.elapsed_time&.to_i
      case
      when t > 60*60
        "#{t/(60*60)} hour #{t%(60*60) / 60} min #{t % 60} sec"
      when t > 60
        "#{t / 60} min #{t % 60} sec"
      else
        "#{t} sec"
      end
    end
  end

  private
  def update_test_status
    TestStatus.update_latest(self)
  end
end

class TestStatus < ActiveRecord::Base
  belongs_to :result

  def self.update_latest(result)
    if test = self.where(name: result.name).first
      test.update(result: result, visible: true)
      test.save
    else
      test = TestStatus.new(name: result.name, visible: true, result: result)
      test.save
    end
  end

  def self.index_all
    self.eager_load(:result).where(visible: true).order(:name)
  end

  def self.index_all_latest
    self.eager_load(:result).where(visible: true).order('results.updated_at desc')
  end
end

# alert
def otps2msg name, opts
  if json = opts[:desc_json]
    summary = JSON.parse(json).map{|key, val|
      case val
      when String
        "#{key}: #{val}"
      when Array
        "#{key}\n" + val.map{|(_lineno, line)|
          "  " + line
        }.join("\n")
      end
    }.join("\n")

    summary = summary[0..8000] + '...' if summary.size > 8000
  end

  <<~EOS
  Alert on #{name}
  result: #{opts[:result]}
  log: #{opts[:detail_link]}
  #{summary}

  #{opts[:desc]}
  memo: #{opts[:memo]}
  EOS
end

def alert name, result, rev, msg, result_id = nil
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
    puts "#{Time.now} #{cmd}"

    # mail
    IO.popen(cmd, 'r+'){|io|
      io.puts "#{url}\n-- \n#{msg}"
      io.close_write
      puts io.read
    }

    # slack notification
    notify_simpler_alerts(name, url, result, rev)
  end
end

def alert_setup name, timeout_str, to
  timeout = (timeout_str || (60 * 60 * 3)).to_i
  to = to.split(/[, ]+/) if to

  WATCH_LIST[name] = {timeout: timeout, alerted: false, to: to}
end

def notify_simpler_alerts name, url, result, rev
  if ENV.key?('SIMPLER_ALERTS_URL') && rev
    params = {
      ci: "ci.rvm.jp",
      env: name,
      url: url,
      commit: rev,
    }
    uri = URI.parse(ENV['SIMPLER_ALERTS_URL'])
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.post(uri.path, JSON.generate(params), { "Content-Type" => "application/json" })
    end
  end
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
else
  STDERR.puts "watch threads are not kicked"
end
