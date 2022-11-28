
require 'fileutils'
require 'open-uri'

ARGV.each{|user|
  password = rand.to_s
  keys = URI.open("https://github.com/#{user}.keys").read

  system("adduser #{user} --disabled-password --gecos \"\"") or raise
  system("echo #{user}:'#{password}' | /usr/sbin/chpasswd") or raise

  homedir = "/home/#{user}"

  File.open(homedir + "/password", 'w', 0400){|f| f.puts password}
  Dir.mkdir(sshdir = homedir + "/.ssh", 0700)
  File.open(sshdir + "/authorized_keys", 'w', 0400){|f| f.puts keys}

  FileUtils.chown_R(user, nil, homedir)
}
