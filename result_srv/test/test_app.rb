
ENV['RACK_ENV'] = 'test'

require_relative '../app'
require 'test/unit'
require 'rack/test'

class ResultServerTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    ResultServer
  end

  def test_index
    get '/'
    assert last_response.ok?
    assert_match /Latest results/, last_response.body
    assert_match /50\s+\/\s+100/, last_response.body
    assert_match /foo/, last_response.body
    assert_match /bar/, last_response.body
    assert_match /baz/, last_response.body
  end

  def test_results
    test_index
  end

  def test_result_name
    test = -> url do
      get url
      assert last_response.ok?, last_response.body
      assert_match /Results of foo/, last_response.body
    end

    test.call '/results/foo'
    test.call '/results/foo/'
  end

  def view_result_id name, id, status = /NG/
    get "/results/#{name}/#{id}"
    assert last_response.ok?, last_response.body
    assert_match "Results of #{name} at", last_response.body, last_response
    assert_match status, last_response.body
  end

  def test_result_name_result_id
    view_result_id 'foo', 1
  end

  def test_post_new_results
    put "/results", name: 'test_example', result: st1='NG<ex1>', desc: 'desc<ex1>', memo: 'memo<ex1>'
    url = last_response.body
    assert_match /\/test_example\//, url
    /\/(\d+)\z/ =~ url
    assert $1
    result_id = $1.to_i
    
    assert !!$last_alert
    assert_equal ["ruby-alerts@quickml.atdot.net"], $last_alert[:to]
    assert_equal "failure alert on test_example (NG<ex1>)", $last_alert[:subject]
    assert_equal "http://ci.rvm.jp/results/test_example/#{result_id}", $last_alert[:url]
    assert_equal "mail -s 'failure alert on test_example (NG<ex1>)' -aFrom:ko1c-failure@atdot.net ruby-alerts@quickml.atdot.net",
                 $last_alert[:cmd]
    assert_equal  "Alert on test_example\nrsult : NG<ex1>\ndetail: \ndesc:\ndesc<ex1>\nmemo:\nmemo<ex1>\n", $last_alert[:msg]
    $last_alert = nil

    put "/results", name: 'test_example', result: st2='OK<ex2>', desc: 'desc<ex2>', memo: 'memo<ex2>'
    assert_equal nil, $last_alert
    view_result_id 'test_example', result_id, CGI.escape_html(st1)
    view_result_id 'test_example', result_id+1, CGI.escape_html(st2)
  end
end
