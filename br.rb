
require 'optparse'

cmd = ARGV.shift

WORKING_DIR = "~/ruby"
BUILD_RUBY_SCRIPT = File.join(File.dirname(__FILE__), 'build-ruby.rb')
case cmd
when 'list'
  Dir.glob(File.join(WORKING_DIR, '*.br')){|file|
    puts File.basename(file, '.br')
  }
when 'build'
  target = ARGV.shift || raise('build target is not provided')
  target_file = File.expand_path(File.join(WORKING_DIR, "#{target}.br"))
  opts = open(target_file){|f|
    f.readlines.map{|line| line.chomp}.join(' ')
  } + ARGV.join(' ')
  p "ruby #{BUILD_RUBY_SCRIPT} #{opts}"
when nil
  raise "command is not provided"
else
  raise "#{cmd} is not supported"
end
