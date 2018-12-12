require 'fileutils'
require_relative 'load_env'

# setup logs
FileUtils.mkdir_p(File.join(CONFIG_DIR, 'logs'), verbose: true)

targets_yaml = File.join(CONFIG_DIR, 'targets.yaml')
raise "#{targets_yaml} already exists." if File.exist?(targets_yaml)
# setup default rules
FileUtils.cp(File.join(__dir__, 'default_targets.yaml'), targets_yaml, verbose: true)
