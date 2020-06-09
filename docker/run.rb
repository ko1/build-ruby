
def run image, config_name, noop = false
  cmd = "docker run --init -d --rm -v ~/ruby:/home/ko1/ruby " + 
        "--name=#{config_name} --hostname=#{`hostname`.strip}-docker " +
        "--cap-add=SYS_PTRACE --tmpfs /tmp:exec " +
        "-e BUILD_RUBY_WORKING_DIR=/tmp/ruby " +
        "#{image} " +
        "ruby #{__dir__}/boot.rb #{config_name} --incremental --process-num=6"
  puts "kick: #{cmd}"
  system cmd unless noop
end

def run_interractive arg
  cmd = "docker run -it --init --rm -v ~/ruby:/home/ko1/ruby " +
        "--name=run_interractive.#{$$}  --hostname=#{`hostname`.strip}-docker " +
        "--cap-add=SYS_PTRACE --tmpfs /tmp:exec " +
        "#{IMAGE_NAME} " + arg
  puts "kick: #{cmd}"
  system cmd

end

if ARGV.empty?

           # trunk-asserts-nopara 
tests = {
  'rubydev:bionic' =>
        %w(trunk_gcc4 trunk_gcc5 trunk_gcc6 trunk_gcc7 trunk_gcc8
           trunk_clang_39 trunk_clang_40 trunk_clang_50 trunk_clang_60
           trunk_clang_7 trunk_clang_8
           trunk-nopara
           trunk-jemalloc
           trunk-asserts
           trunk-vm-asserts trunk-gc-asserts
           trunk-theap-asserts
           trunk-no-theap
           trunk-mjit trunk-mjit-wait
           trunk-no-mjit
           trunk-iseq_binary
           trunk-iseq_binary-nopara
           trunk-gc_compact
           trunk-O0
           trunk-cross-mingw64
        ),
  'rubydev:focal' =>
        %w(trunk_gcc9 trunk_gcc10
	   trunk_clang_9 trunk_clang_10
        ),
}


# clean
if ENV['CLEAN_ALL'] == 'true'
  tests.each{|image, tests|
    tests.each{|test|
      system("docker kill #{test}")
      system("ruby ~/ruby/build-ruby/br.rb build #{test} --rm=all")
    }
  }
  exit
end

if ENV['NOOP'] == 'true'
  tests.each{|image, tests|
    tests.each{|test|
      run image, test, true
    }
  }
  exit
end

ps = `docker ps --no-trunc`

tests.each{|image, tests|
  tests.each{|test|
    if /^(.+#{test}.+)$/ =~ ps
      STDERR.puts "#{test} is already launched: #{$1}"
    else
      run image, test
      st = rand(30)
      puts "sleep #{st}"
      sleep rand(st)
    end
  }
}

else
  run_interractive ARGV.join(' ')
end

