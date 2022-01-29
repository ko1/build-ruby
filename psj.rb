
def psj logger
  rel = Hash.new{|h, k| h[k] = []}
  logger.error "$$$ ps jx"
  `ps jx`.each_line{|line|
    logger.error line.chomp
    if /\A\s*(\d+)\s+(\d+)\s+\d+\s+\d+/ =~ line
      ppid, pid = $1.to_i, $2.to_i
      rel[ppid] << pid
    end
  }
  logger.error rel.inspect
  rel
end

def each_descendant pid, logger, rel = psj(logger), &b
  if children = rel[pid]
    children.each{|child|
      each_descendant(child, logger, rel, &b)
      yield child
    }
  end
end

def kill_descendant_with_gdb_info logger, pid = Process.pid
  each_descendant(pid, logger) do |pid|
    gdbscript = File.expand_path(File.join(__dir__, "gdbscript"))
    gdb_command = "timeout 60 gdb -p #{pid} -x #{gdbscript} -batch -quiet 2> /dev/null"
    logger.error "$ #{gdb_command}"

    gdb_pid = IO.popen(gdb_command, 'r'){|io|
      while line = io.gets
        logger.error line.chomp
      end
    }

    begin
      Process.kill :KILL, pid
    rescue Errno::ESRCH => e
      logger.error e.inspect
    end
  end
end

if $0 == __FILE__
  pids = 3.times.map{
    spawn("~/ruby/build/trunk/miniruby -esleep")
  }

  kill_descendant_with_gdb_infojj
end
