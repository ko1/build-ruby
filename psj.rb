
def psj
  rel = Hash.new{|h, k| h[k] = []}
  puts "$$$ ps jx"
  `ps jx`.each_line{|line|
    puts line
    if /\A\s*(\d+)\s+(\d+)\s+\d+\s+\d+/ =~ line
      ppid, pid = $1.to_i, $2.to_i
      rel[ppid] << pid
    end
  }
  rel
end

def each_descendant pid, rel = p(psj()), &b
  if children = rel[pid]
    children.each{|child|
      each_descendant(child, rel, &b)
      yield child
    }
  end
end

def kill_descendant_with_gdb_info pid = Process.pid
  each_descendant(pid) do |pid|
    gdbscript = File.expand_path(File.join(__dir__, "gdbscript"))
    gdb_command = "timeout 60 gdb -p #{pid} -x #{gdbscript} -batch -quiet"
    p gdb_command; STDOUT.flush
    gdb_pid = IO.popen(gdb_command, 'r'){|io|
      while line = io.gets
        puts line
        STDOUT.flush
      end
    }
    p [gdb_pid, pid]
    STDOUT.flush
    begin
      Process.kill :KILL, pid
    rescue Errno::ESRCH => e
      p e
      # ignore
    end
  end
end

if $0 == __FILE__
  pids = 3.times.map{
    spawn("~/ruby/build/trunk/miniruby -esleep")
  }

  kill_descendant_with_gdb_info
end
