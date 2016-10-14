#!/usr/bin/ruby

require 'fileutils'
require 'optparse'
require 'pp'
require 'logger'
require 'benchmark'
require 'etc'

class BuildRuby
  def initialize repository = nil,
                 target_name = nil,
                 repository_type: nil,
                 branch_name: nil,
                 root_directory: "~/ruby",
                 build_opts: nil,
                 test_opts: nil,
                 steps: nil,
                 logfile: "log.build-ruby-#{Time.now.strftime('%Y%m%d-%H%M%S')}"
    #
    @REPOSITORY      = repository      || 'https://svn.ruby-lang.org/repos/ruby/trunk'
    @REPOSITORY_TYPE = repository_type || find_repository_type(@REPOSITORY)
    @TARGET_NAME     = target_name     || File.basename(@REPOSITORY)

    @SRC_DIR     = File.expand_path(File.join(root_directory, 'src'))
    @BUILD_DIR   = File.expand_path(File.join(root_directory, 'build'))
    @INSTALL_DIR = File.expand_path(File.join(root_directory, 'install'))
    @TARGET_SRC_DIR = File.join(@SRC_DIR, @TARGET_NAME)
    @TARGET_BUILD_DIR = File.join(@BUILD_DIR, @TARGET_NAME)

    @branch_name = branch_name

    if Etc.respond_to? :nprocessors
      pn = Etc.nprocessors
      build_opts ||= "-j#{pn}"
      test_opts  ||= "TESTS='-j#{pn}'"
    end
    @build_opts = build_opts
    @test_opts = test_opts

    @steps = steps || %w{
      checkout
      autoconf
      configure
      build_up
      build_miniruby
      build_ruby
      build_exts
      build_all
      build_install
      test_btest
      test_all
      test_rubyspec
    }

    STDERR.puts "Logfile: #{logfile}"
    @logfile = logfile
    @logger = Logger.new(logfile)
  end

  def find_repository_type repository
    case repository
    when /git/
      :git
    when /svn/
      :svn
    else
      raise "unkown repository type: #{repository}"
    end
  end

  def show_config
    h = [:@REPOSITORY, :@REPOSITORY_TYPE, :@TARGET_NAME,
     :@SRC_DIR, :@BUILD_DIR, :@INSTALL_DIR, :@TARGET_SRC_DIR, :@TARGET_BUILD_DIR,
     :@build_opts, :@test_opts, :@steps, :@logfile].inject({}){|h, k|
      h[k] = self.instance_variable_get(k); h
    }
    @logger.info h.inspect
  end

  def setup_dir
    # setup directories
    FileUtils.mkdir_p(@SRC_DIR)            unless File.exist?(@SRC_DIR)
    FileUtils.mkdir_p(@TARGET_BUILD_DIR)   unless File.exist?(@TARGET_BUILD_DIR)
    FileUtils.mkdir_p(@INSTALL_DIR)        unless File.exist?(@INSTALL_DIR)
  end

  def cmd *args
    cmd_str = args.join(' ')
    @logger.info cmd_str
    IO.popen(cmd_str, 'r+', err: [:child, :out]){|io|
      io.each_line{|line|
        @logger.info line.chomp
      }
    }
    raise "command failed: #{cmd_str} (exit with #{$?.to_i})." unless $?.success?
  end

  def checkout
    return if File.exist?(@TARGET_SRC_DIR)
    Dir.chdir(@SRC_DIR){
      case @REPOSITORY_TYPE
      when :svn
        cmd 'svn', 'checkout', @REPOSITORY, @TARGET_NAME
      when :git
        if @branch_name
          cmd 'git', 'clone', '--depth', '1', '-b', @branch_name, '--single-branch', @REPOSITORY, @TARGET_NAME
        else
          cmd 'git', 'clone', '--depth', '1', @REPOSITORY, @TARGET_NAME
        end
      else
        raise "unknown repository type: #{@REPOSITORY_TYPE}"
      end
    }
  end

  def autoconf
    Dir.chdir(File.join(@SRC_DIR, @TARGET_NAME)){
      cmd 'autoconf'
    }
  end

  def builddir
    Dir.chdir(@TARGET_BUILD_DIR){
      yield
    }
  end

  def build
    configure
    build_up
    build_all
    build_install
  end

  def configure
    builddir{
      unless File.exist? File.join(@TARGET_BUILD_DIR, 'Makefile')
        cmd File.join(@TARGET_SRC_DIR, 'configure'), '--disable-install-doc', '--enable-shared', "--prefix=#{@INSTALL_DIR}"
      end
    }
  end

  def build_up
    builddir{
      cmd "make up #{@build_opts}"
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
      cmd "make exts #{@build_opts}"
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
      cmd "make btest #{@test_opts}"
    }
  end

  def test_all
    builddir{
      cmd "make test-all #{@test_opts}"
    }
  end

  def test_rubyspec
    builddir{
      cmd "make test-rubyspec #{@test_opts}"
    }
  end

  def run
    err = nil
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
    puts "total: #{'%0.2f' % tm.real} sec"
    raise err if err
  end
end

opts = {}

opt = OptionParser.new
opt.on('--repository_type=[TYPE]'){|type|
  opts[:repository_type] = type
}
opt.on('--branch_name=[BRANCH_NAME]'){|b|
  opts[:branch_name] = b
}
opt.on('--build_opts=[BUILD_OPTS]'){|o|
  opts[:build_opts] = o
}
opt.on('--root_directory=[ROOT_DIR]'){|dir|
  opts[:root_directory] = dir
}
opt.on('--test_opts=[TEST_OPTS]'){|o|
  opts[:test_opts] = o
}
opt.on('--steps=["STEP1 STEP2..."]'){|steps|
  opts[:steps] = steps.split(/\s+/)
}
opt.on('--logfile=[LOGFILE]'){|logfile|
  opts[:logfile] = logfile
}
opt.on('--install-only'){
  opts[:steps] = %w{
    checkout
    autoconf
    configure
    build_up
    build_miniruby
    build_ruby
    build_exts
    build_all
    build_install
  }
}

opt.parse!(ARGV)
repository = ARGV.shift
target_name = ARGV.shift
br = BuildRuby.new(repository, target_name, **opts)
br.show_config
br.setup_dir
br.run
