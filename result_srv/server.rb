
class ResultServer < Sinatra::Base
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
end

