
%w(foo bar baz).each{|name|
  10.times{|i|
    # old format
    result = (i%2) == 0 ? 'OK (old)' : 'NG (old)'
    r = Result.new(name: name,
                   result: result,
                   desc: "long desc #{i}\n" * 20,
                   detail_link: 'http://example.com',
                   memo: 'memo')
    r.save
  }
  10.times{|i|
    # new format
    result = (i%2) == 0 ? 'OK (new)' : 'NG (new)'
    r = Result.new(name: name,
                   result: result,
                   desc: "hogehoge#{i}\n" * 20,
                   detail_link: "/logfiles/log.sample",
                   memo: 'memomemo',
                   desc_json: <<~'EOS'
                   {"exit_results":[[2,"\"make update-unicode  -j12\" exit with 0."],[27,"\"make update-download -j12\" exit with 0."],[35,"\"make update-rubyspec -j12\" exit with 0."],[38,"\"make update-src      -j12\" exit with 0."],[39,"stderr: From https://github.com/ruby/ruby"],[40,"stderr:    cc8064b..bffd6cb  master     -> origin/master"],[51,"\"make after-update    -j12\" exit with 512."],[822,"stderr: make[1]: *** No rule to make target 'id.h', needed by 'ripper.y'.  Stop."],[826,"stderr: make: *** [uncommon.mk:1198: /home/ko1/ruby/v3/src/trunk/ext/ripper/ripper.c] Error 2"],[827,"stderr: make: *** Waiting for unfinished jobs...."],[832,"\"make miniruby -j12\" exit with 0."],[938,"\"make ruby -j12\" exit with 0."],[970,"\"make all -j12\" exit with 0."],[1668,"\"make install -j12\" exit with 0."],[1872,"\"make yes-btest TESTOPTS=-q TESTS='-j12'\" exit with 0."],[1875,"\"make yes-test-basic TESTS='-j12'\" exit with 0."],[1927,"\"make yes-test-all TESTOPTS='--stderr-on-failure' TESTS='-j12'\" exit with 512."],[1943,"stderr:   1) Failure:"],[1944,"stderr: TestFoo#test_foo [/home/ko1/ruby/v3/src/trunk/test/ruby/test_foo.rb:6]:"],[1945,"stderr: Expected true to be nil."],[1951,"stderr: make: *** [uncommon.mk:821: yes-test-all] Error 1"],[1953,"\"make yes-test-rubyspec TESTS='-j12'\" exit with 0."],[1954,"stderr: $ /home/ko1/ruby/v3/build/trunk/miniruby -I/home/ko1/ruby/v3/src/trunk/lib /home/ko1/ruby/v3/src/trunk/tool/runruby.rb --archdir=/home/ko1/ruby/v3/build/trunk --extout=.ext -- /home/ko1/ruby/v3/src/trunk/spec/mspec/bin/mspec-run -B /home/ko1/ruby/v3/src/trunk/spec/default.mspec"]],"rev":"bffd6cbd97","test_all":"21887 tests, 5906405 assertions, 1 failures, 0 errors, 88 skips","test_spec":"3821 files, 30940 examples, 195767 expectations, 0 failures, 0 errors, 0 tagged"}
                   EOS
                 )
    r.save
  }
}
