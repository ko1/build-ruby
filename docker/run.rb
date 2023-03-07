
def run image, config_name, noop = false
  cmd = "docker run --memory=16g --init -d --rm -v ~/ruby:/home/ko1/ruby " + 
        "--name=#{config_name} --hostname=#{`hostname`.strip}-docker " +
        "--cap-add=SYS_PTRACE --tmpfs /tmp:exec " +
        "-e BUILD_RUBY_WORKING_DIR=/tmp/ruby " +
        "#{image} " +
        "ruby #{__dir__}/boot.rb #{config_name} --incremental --process-num=6"
  puts "kick: #{cmd}"
  system cmd unless noop
end

def run_interractive arg
  image = 'rubydev:focal'
  cmd = "docker run -it --init --rm -v ~/ruby:/home/ko1/ruby " +
        "--name=run_interractive.#{$$}  --hostname=#{`hostname`.strip}-docker " +
        "--cap-add=SYS_PTRACE --tmpfs /tmp:exec " +
        "#{image} " + arg
  puts "kick: #{cmd}"
  system cmd

end

if ARGV.empty?

tests = {
  'rubydev:focal' => %w{
    trunk-random0
    trunk-random1
    trunk-random2
    trunk-random3
    trunk-repeat20
    trunk-repeat20-asserts
    trunk-repeat50
    trunk-random-repeat

    trunk-gc-asserts
    trunk-asserts
    trunk-iseq_binary
    trunk-no-mjit
    trunk-yjit
    trunk-O0
    master-mjit
  },
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

