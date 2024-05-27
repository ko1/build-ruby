
# now it introduces failures
  # modify hosts
  # hosts=File.readlines("/etc/hosts").reject{|line|/::/=~line}
  # File.write("/etc/hosts", hosts.join)

# exec
test_opts = ARGV.join(" ")
t = Thread.new{
  system("cd /home/ko1/ruby/build-ruby/ && su ko1 -c 'PATH=/usr/lib/ccache:$PATH CCACHE_DIR=/tmp/ccache sh build-loop.sh #{test_opts}'")
}

system("ps ax")

Signal.trap(:SIGCHLD) do
  begin
    while pid = Process.waitpid(-1, Process::WNOHANG)
      STDERR.puts "!!!!!!!!!!!!!!!!!!!!!!!!!! Process #{pid} is dead."
    end
  rescue Errno::ECHILD
    # ignore
  end
end

t.join

