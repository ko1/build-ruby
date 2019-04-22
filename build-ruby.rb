#!/usr/bin/ruby

require 'fileutils'
require 'optparse'
require 'pp'
require 'logger'
require 'benchmark'
require 'etc'
require 'timeout'

class BuildRuby
  BUILD_STEPS = %w{
    checkout
    autoconf
    configure
    build_up
    build_miniruby
    build_ruby
    build_all
    build_install
  }
  TEST_STEPS = %w{
    test_btest
    test_basic
    test_all
    test_rubyspec
  }
  CLEANUP_STEPS = %w{
    cleanup_src
    cleanup_build
  }

  def nproc
    if Etc.respond_to?(:nprocessors)
      Etc.nprocessors
    else
      nil
    end
  end

  def initialize repository = nil,
                 target_name = nil,
                 repository_type: nil,
                 git_branch: nil,
                 svn_revision: nil,
                 root_dir: "~/ruby",
                 src_dir: nil,
                 build_dir: nil,
                 install_dir: nil,
                 configure_opts: nil,
                 build_opts: nil,
                 test_opts: nil,
                 no_parallel: false,
                 process_num: nproc,
                 incremental: false,
                 steps: BUILD_STEPS + TEST_STEPS,
                 exclude_steps: [],
                 logfile: nil,
                 quiet: false,
                 gist: false,
                 timeout: nil
    #
    @REPOSITORY      = repository      || 'https://github.com/ruby/ruby.git'
      # 'https://svn.ruby-lang.org/repos/ruby/trunk'
    @REPOSITORY_TYPE = (repository_type || find_repository_type(@REPOSITORY)).to_sym

    @git_branch = git_branch
    @svn_revision = svn_revision
    basename = File.basename(@REPOSITORY)

    @TARGET_NAME = target_name ||
                   case
                   when @git_branch
                     "#{basename}_#{@git_branch}"
                   when @svn_revision
                     "#{basename}_r#{@svn_revision}"
                   else
                     basename
                   end

    @SRC_DIR     = File.expand_path(File.join(root_dir, 'src', @REPOSITORY_TYPE.to_s))
    @BUILD_DIR   = File.expand_path(File.join(root_dir, 'build'))
    @INSTALL_DIR = File.expand_path(File.join(root_dir, 'install'))
    @TARGET_SRC_DIR     = File.join(@SRC_DIR,     src_dir     || @TARGET_NAME)
    @TARGET_BUILD_DIR   = File.join(@BUILD_DIR,   build_dir   || @TARGET_NAME)
    @TARGET_INSTALL_DIR = File.join(@INSTALL_DIR, install_dir || @TARGET_NAME)

    if process_num && no_parallel == false
      build_opts ||= "-j#{process_num}"
      test_opts  ||= "TESTS='-j#{process_num}'"
    end
    @configure_opts = configure_opts || ['--enable-shared']
    @build_opts = build_opts
    @test_opts = test_opts
    @incremental = incremental

    exclude_steps.each{|step|
      steps.delete(step)
    }

    @steps = steps
    @quiet = quiet
    @gist = gist
    @timeout = timeout

    logfile ||= "log.build-ruby.#{@TARGET_NAME}.#{Time.now.strftime('%Y%m%d-%H%M%S')}"

    @logfile = logfile
  end

  def find_repository_type repository
    case repository
    when /git/
      :git
    when /svn/
      :svn
    else
      if File.exist?(repository) && File.exist?(File.join(repository, '.git'))
        :git
      else
        raise "unkown repository type: #{repository}"
      end
    end
  end

  def show_config
    pp self unless @quiet
  end

  def setup_dir
    # setup directories
    FileUtils.mkdir_p(@SRC_DIR)            unless File.exist?(@SRC_DIR)
    FileUtils.mkdir_p(@TARGET_BUILD_DIR)   unless File.exist?(@TARGET_BUILD_DIR)
    FileUtils.mkdir_p(@INSTALL_DIR)        unless File.exist?(@INSTALL_DIR)
  end

  class CmdFailure < StandardError
  end

  def cmd *args, on_failure: :raise
    cmd_str = args.join(' ')
    @logger.info "$$$[beg] #{cmd_str}"
    IO.popen(cmd_str, 'r+'){|io|
      if @timeout
        begin
          Timeout.timeout(@timeout) do
            io.each_line{|line|
              @logger.info line.chomp
            }
          end
        rescue Interrupt, Timeout::Error
          STDERR.puts "$$$ #{$!.inspect}"
          require_relative 'psj'
          kill_descendant_with_gdb_info
          raise
        end
      else
        io.each_line{|line|
          @logger.info line.chomp
        }
      end
    }
    @logger.info exit_str = "$$$[end] #{cmd_str.dump} exit with #{$?.to_i}."

    if !$?.success?
      case on_failure
      when :raise
        raise CmdFailure, exit_str
      when :skip
        @failures << exit_str
      when :ignore
        # ignore
      else
        raise
      end
    end
  end

  def checkout
    return if File.exist?(@TARGET_SRC_DIR)
    Dir.chdir(@SRC_DIR){
      case @REPOSITORY_TYPE
      when :svn
        if @svn_revision
          cmd 'svn', 'checkout', '-q', "-r#{@svn_revision}", @REPOSITORY, @TARGET_NAME
        else
          cmd 'svn', 'checkout', '-q', @REPOSITORY, @TARGET_NAME
        end
      when :git
        if @git_branch
          cmd 'git', 'clone', '--depth', '1', '-b', @git_branch, '--single-branch', @REPOSITORY, @TARGET_NAME
        else
          cmd 'git', 'clone', '--depth', '1', @REPOSITORY, @TARGET_NAME
        end
      else
        raise "unknown repository type: #{@REPOSITORY_TYPE}"
      end
    }
  end

  def autoconf
    Dir.chdir(@TARGET_SRC_DIR){
      unless File.exist?('configure')
        cmd 'autoconf'
      end
    }
  end

  def builddir
    Dir.chdir(@TARGET_BUILD_DIR){
      yield
    }
  end

  def configure
    builddir{
      unless File.exist? File.join(@TARGET_BUILD_DIR, 'Makefile')
        cmd File.join(@TARGET_SRC_DIR, 'configure'), "--prefix=#{@TARGET_INSTALL_DIR}", '--disable-install-doc', *@configure_opts
      end
    }
  end

  def build_up
    builddir{
      cmd "rm -f .revision.time" # to check correct rev.
      cmd "make update-download #{@build_opts}", on_failure: :ignore
      cmd "make update-rubyspec #{@build_opts}", on_failure: :ignore if @steps.include?('test_rubyspec')
      cmd "make update-src      #{@build_opts}", on_failure: :ignore unless @svn_revision
      cmd "make after-update    #{@build_opts}", on_failure: :ignore
    }
  end

  def build_miniruby
    builddir{
      cmd "make miniruby #{@build_opts}"
    }
  end

  def build_ruby
    builddir{
      cmd "make ruby #{@build_opts}"
    }
  end

  def build_exts
    builddir{
      cmd "make exts #{@build_opts}", on_failure: :ignore
    }
  end

  def build_all
    builddir{
      cmd "make all #{@build_opts}"
    }
  end

  def build_install
    builddir{
      cmd "make install #{@build_opts}"
    }
  end

  def check
    builddir{
      cmd "make check #{@test_opts}"
    }
  end

  def test_btest
    builddir{
      cmd "make yes-btest #{@test_opts}", on_failure: :skip
    }
  end

  def test_basic
    builddir{
      cmd "make yes-test-basic #{@test_opts}", on_failure: :skip
    }
  end

  def test_all
    builddir{
      cmd "make yes-test-all #{@test_opts}", on_failure: :skip
    }
  end

  def test_rubyspec
    builddir{
      cmd "make yes-test-rubyspec #{@test_opts}", on_failure: :skip
    }
  end

  def cleanup_src
    remove [:src]
  end

  def cleanup_build
    remove [:build]
  end

  def run
    @logger = Logger.new(@logfile)
    @logger.info self.inspect
    @failures = []

    err = nil
    return unless @incremental || !File.exist?(File.join(@TARGET_INSTALL_DIR, 'bin/ruby'))

    STDERR.puts "Logfile: #{@logfile}" unless @quiet

    do_steps = Proc.new{
      @steps.each{|step|
          x.report(step){
            begin
              send(step)
            rescue => e
              err = e
            end
          }
          break if err
        }
    }

    if @quet
      @steps.each{|step|
        begin
          send(step)
        rescue => e
          err = e
        end
      }
    else
      tm = Benchmark.measure{
        Benchmark.bm(20){|x|
          @steps.each{|step|
            x.report(step){
              begin
                send(step)
              rescue => e
                err = e
              end
            }
            break if err
          }
        }
      }
      puts "total: #{'%0.2f' % tm.real} sec" unless @quiet
    end

    # check err
    case err
    when CmdFailure
      STDERR.puts err.message
      exit_failure
    when nil
      # ignore
    else
      raise err
    end

    # check failures
    unless @failures.empty?
      @failures.each{|f|
        STDERR.puts f
      }
      exit_failure
    end
  end

  def exit_failure
    STDERR.puts @logfile
    system("gist -p #{@logfile}") if @gist
    exit 1
  end

  def remove types
    types.each{|type|
      case type
      when :all
        FileUtils.rm_rf(p @TARGET_SRC_DIR)
        FileUtils.rm_rf(p @TARGET_BUILD_DIR)
        FileUtils.rm_rf(p @TARGET_INSTALL_DIR)
      when :build
        FileUtils.rm_rf(p @TARGET_BUILD_DIR)
      when :install
        FileUtils.rm_rf(p @TARGET_INSTALL_DIR)
      when :src
        FileUtils.rm_rf(p @TARGET_SRC_DIR)
      end
    }
  end
end

opts = {}
rm_types = nil

opt = OptionParser.new
opt.on('--repository_type=[TYPE]'){|type|
  opts[:repository_type] = type
}
opt.on('-b', '--git_branch=[BRANCH_NAME]'){|b|
  opts[:git_branch] = b
}
opt.on('-r', '--svn_revision=[REV]'){|r|
  opts[:svn_revision] = r
}
opt.on('--configure_opts=[CONFIGURE_OPTS]'){|o|
  opts[:configure_opts] = [o]
}
opt.on('--build_opts=[BUILD_OPTS]'){|o|
  opts[:build_opts] = o
}
opt.on('--root_dir=[ROOT_DIR]'){|dir|
  opts[:root_dir] = dir
}
opt.on('--src_dir=[SRC_DIR]'){|dir|
  opts[:src_dir] = dir
}
opt.on('--build_dir=[BUILD_DIR]'){|dir|
  opts[:build_dir] = dir
}
opt.on('--install_dir=[INSTALL_DIR]'){|dir|
  opts[:install_dir] = dir
}
opt.on('--test_opts=[TEST_OPTS]'){|o|
  opts[:test_opts] = o
}
opt.on('--steps=["STEP1 STEP2..."]'){|steps|
  opts[:steps] = steps.split(/\s+/)
}
opt.on('--exclude-steps=["STEP1 STEP2..."]'){|steps|
  opts[:exclude_steps] = steps.split(/\s+/)
}
opt.on('--logfile=[LOGFILE]'){|logfile|
  opts[:logfile] = logfile
}
opt.on('--clear'){
  rm_types = [:all]
}
opt.on('--rm=[all|src|build|install]'){|types|
  if types
    rm_types = types.split(/[\s,]+/).map{|e| e.to_sym}
  else
    rm_types = [:all]
  end
}
opt.on('--no-parallel'){
  opts[:no_parallel] = true
}
opt.on('--process-num=[NUM]'){|n|
  opts[:process_num] = n.to_i
}
opt.on('--incremental'){
  opts[:incremental] = true
}
opt.on('--only-install'){
  opts[:steps] = BuildRuby::BUILD_STEPS
}
opt.on('--only-install-cleanup'){
  opts[:steps] = BuildRuby::BUILD_STEPS + BuildRuby::CLEANUP_STEPS
}
opt.on('-q', '--quiet'){
  opts[:quiet] = true
}
opt.on('--gist'){
  opts[:gist] = true
}
opt.on('--timeout=[TIMEOUT]'){|timeout|
  opts[:timeout] = timeout.to_i
}
target_name = nil
opt.on('--target_name=[TARGET_NAME]'){|t|
  target_name = t
}
opt.on('--add-path=[ADDITIONAL_PATH]'){|path|
  ENV['PATH'] = [path, ENV['PATH']].join(File::PATH_SEPARATOR)
}
opt.on('--add-env=[VAR=VAL]'){|env|
  val, var = env.split('=')
  raise "--add-env receives ill-formed env: #{env}" if !val || !var
  ENV[val] = var
}

opt.parse!(ARGV)

repository = ARGV.shift
target_name ||= ARGV.shift

br = BuildRuby.new(repository, target_name, **opts)
br.show_config

if rm_types
  br.remove rm_types
else
  br.setup_dir
  br.run
end
