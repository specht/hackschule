#!/usr/bin/env ruby

system("cd ../.. && cat \"#{ARGV.first}\" | docker exec -i $(./config.rb ps -q ruby) ruby load-dump.rb /dev/stdin && cd src/scripts")
