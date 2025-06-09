IMAGE = 'rubydev:noble'

def kick image, cmd, config_name, run_opt, noop
  uver = image.scan(/.+:(.+)/)&.first&.first || image

  cmd = "docker run #{run_opt} --memory=6g --init --rm " +
        # "--tmpfs /tmp:exec " +
        "-v #{__dir__}/ruby:/home/ko1/ruby " + 
        "-v #{__dir__}/../:/home/ko1/build-ruby " +
        "-v /var/run/docker.sock:/var/run/docker.sock " +
        # "-v /tmp:/tmp " +
        "--name=#{config_name} --hostname=#{`hostname`.strip}-#{uver}-docker " +
        "--cap-add=SYS_PTRACE --privileged " +
        "-e BUILD_RUBY_WORKING_DIR=/tmp/ruby " +
        "#{image} #{cmd}"
  puts "kick: #{cmd}"
  system cmd unless noop
end

def run image, config_name, noop = false
  kick image, "ruby /home/ko1/ruby/boot.rb #{config_name} --incremental --process-num=4", config_name, '-d', noop
end

def run_interractive arg, noop = false
  image = 'rubydev:noble'
  kick image, arg, "run_interractive.#{$$}", '-it', noop
end

if ARGV.empty?

  # no memory...
  # trunk-random3
  # trunk-random-repeat

tests = {
  IMAGE => %w{
    trunk-random0
    trunk-random1
    trunk-random2

    trunk-repeat20
    trunk-repeat20-asserts
    trunk-repeat50

    trunk-gc-asserts
    trunk-asserts-nopara
    trunk-iseq_binary
    trunk-O0
    trunk-jemalloc

    trunk_gcc10
    trunk_gcc11
    trunk_gcc12
    trunk_gcc13
    trunk_gcc14

    trunk_clang_14
    trunk_clang_15
    trunk_clang_16
    trunk_clang_17
    trunk_clang_18

    trunk-yjit

    master-no-rjit
  },
  # trunk-yjit-asserts
  # master-rjit
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
    if /^(.+#{test}\s+.+)$/ =~ ps
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



