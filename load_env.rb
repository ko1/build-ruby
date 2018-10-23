
WORKING_DIR = File.expand_path(ENV['BUILD_RUBY_WORKING_DIR'] || "~/ruby")
BUILD_RUBY_SCRIPT = File.join(File.dirname(__FILE__), 'build-ruby.rb')
PAGER = ENV['PAGER'] || 'less'

# load TARGETS
TARGETS = {}
def merge_targets yaml
  if File.exist? yaml
    TARGETS.merge! YAML.load_file(yaml)
  end
end

merge_targets File.join(__dir__, 'default_targets.yaml')
merge_targets File.join(WORKING_DIR, 'targets.yaml')

Dir.glob(File.join(WORKING_DIR, '*.br')){|file|
  target = File.basename(file, '.br')
  TARGETS[target] = File.read(file)
}

# default setting
BR_LOOP_MINIMUM_DURATION = (ENV['BR_LOOP_MINIMUM_DURATION'] || (60 * 2)).to_i # 2 min for default
BR_BUILD_TIMEOUT         = (ENV['BR_BUILD_TIMEOUT'] || 3 * 60 * 60).to_i      # 3 hours for default
BR_ALERT_TO              = (ENV['BR_ALERT_TO'] || '')                         # use default
BR_REPORT_HOST           = (ENV['BR_REPORT_HOST'] || 'ci.rvm.jp')             # report host

Target = Struct.new(:arg,
                    :loop_minimum_duration,
                    :build_timeout,
                    :alert_to,
                    :report_host)

# setup params
TARGETS.each{|target_name, config|
  config = '' unless config
  config = {'arg' => config} if config.kind_of? String

  target = Target.new(
    config.delete('arg') { raise 'arg is not given' },
    config.delete('loop_minimum_duration') { BR_LOOP_MINIMUM_DURATION },
    config.delete('build_timeout') { BR_BUILD_TIMEOUT },
    config.delete('alert_to') { BR_ALERT_TO },
    config.delete('report_host') { BR_REPORT_HOST })
  raise "not supported configuration: #{config.inspect}" unless config.empty?

  TARGETS[target_name] = target
}
