core_pattern = '/tmp/cores/core.%u.%p.%e'

open("/etc/sysctl.d/99-ci_rvm_setup.conf", 'w') do |f|
  f.puts <<~EOC
  #
  # Setup for ci.rvm.jp
  #
  
  kernel.yama.ptrace_scope = 0
  kernel.core_pattern = #{core_pattern}
  EOC
end

system("echo #{core_pattern} > /proc/sys/kernel/core_pattern")

Dir.mkdir('/tmp/cores')
File.chmod(077, '/tmp/cores')
