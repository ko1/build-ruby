
%w(foo bar baz).each{|name|
  100.times{|i|
    result = i >= 50 ? 'OK (xxx)' : 'NG (yyy)'
    r = Result.new(name: name, result: result,  desc: "long desc #{i}" * 100, detail_link: 'http://example.com', memo: 'memo')
    r.save
  }
}
