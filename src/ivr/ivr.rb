#!/usr/bin/env ruby

require 'sinatra'
require 'json'
require 'yaml'
require 'open3'
require 'timeout'

class Main < Sinatra::Base
    def self.launch_script(call_id, script_path)
        STDERR.puts "Launching script #{script_path}..."
        path = "/tmp/script-#{call_id}.py"
        File.open(path, 'w') do |f|
            script = File.read(script_path)
            f.puts(@@header)
            f.puts(script)
            f.puts "game = Game(sys.stdout)"
            f.puts "game.run()"
            f.puts "game.hangup()"
        end
        notify = IO.pipe
        stdin, stdout, thread = Open3.popen2('python3', path, '--ivr')
        {:stdin => stdin, :stdout=> stdout, :thread => thread, :notify => notify}
    end

    def self.handle_buffer_for_call(call_id)
        while !(@@info_for_call_id[call_id][:buffer].index("\n").nil?)
            nli = @@info_for_call_id[call_id][:buffer].index("\n")
            line = @@info_for_call_id[call_id][:buffer][0, nli]
            @@info_for_call_id[call_id][:buffer] = @@info_for_call_id[call_id][:buffer][nli + 1, @@info_for_call_id[call_id][:buffer].size]
            data = JSON.parse(line)
            STDERR.puts ">> #{data.to_json}"
            if data['path']
                @@info_for_call_id[call_id][:last_path] = data['path']
            elsif data['get_dtmf']
                @@info_for_call_id[call_id][:notify][1].puts("hey")
            elsif data['command'] == 'hangup'
                @@info_for_call_id[call_id][:notify][1].puts("hey")
            end
        end
    end

    def self.kill_call(call_id)
        @@info_for_call_id[call_id][:thread].kill
        @@info_for_call_id[call_id][:notify][1].puts("hey")
        @@info_for_call_id.delete(call_id)
        @@watcher_ping[1].puts("hey")
    end

    configure do
        STDERR.puts "Configuring IVR"
        parts = File.read(Dir['/tasks/**/*telefonspiel.txt'].first).split('-' * 8).map { |x| x.strip }
        @@header = nil
        parts.each do |part|
            if part.index('[custom_main_pre]') == 0
                @@header = part.sub('[custom_main_pre]', '').strip
            end
        end
        File.open('/ivr/header.py', 'w') do |f|
            f.write @@header
        end
        @@info_for_call_id = {}
        @@watcher_ping = IO.pipe
        @@call_id_for_stdout_fd = {}
        Thread.new do
            STDERR.puts "[WATCHER] I'm a watcher thread!"
            loop do
                read_sockets = []
                read_sockets << @@watcher_ping[0]
                @@info_for_call_id.each_pair do |call_id, info|
                    read_sockets << info[:stdout]
                end
                STDERR.puts "[WATCHER] Waiting on #{read_sockets.size} sockets"
                streams = IO.select(read_sockets)
                STDERR.puts "[WATCHER] Got something"
                streams.first.each do |io|
                    call_id = @@call_id_for_stdout_fd[io.fileno]
                    STDERR.puts "[WATCHER] call id: #{call_id}"
                    if call_id
                        if io.eof?
                            STDERR.puts "[WATCHER] Script has finished, kill it!"
                            self.kill_call(call_id)
                        else
                            STDERR.puts "[WATCHER] Got a response for #{call_id}!"
                            buf = io.read_nonblock(1024)
                            @@info_for_call_id[call_id][:buffer] += buf
                            self.handle_buffer_for_call(call_id)
                        end
                    else
                        s = io.read_nonblock(1024)
                    end
                end
            end
        end
    end

    post '/ivr/' do
        form = request.body.read
        decoded_form = URI.decode_www_form(form)
        data = Hash[decoded_form]
        STDERR.puts "SIPGATE >> #{data.to_json}"
        call_id = data['callId']
        event = data['event']
        if event == 'newCall'
            @@info_for_call_id[call_id] = self.class.launch_script(call_id, "/app/ivr_entry.py")
            @@info_for_call_id[call_id][:last_path] = nil
            @@info_for_call_id[call_id][:buffer] = ''
            @@call_id_for_stdout_fd[@@info_for_call_id[call_id][:stdout].fileno] = call_id
            @@watcher_ping[1].puts("hey")
        elsif event == 'dtmf'
            dtmf = data['dtmf']
            if dtmf.empty? || dtmf == '-1'
                self.class.kill_call(call_id)
            else
                @@info_for_call_id[call_id][:stdin].puts(dtmf)
            end
        end
        return unless @@info_for_call_id[call_id]
        Timeout::timeout(30) do
            STDERR.puts "[MAIN] Waiting for answer from thread for #{call_id}..."
            sockets = IO.select([@@info_for_call_id[call_id][:notify][0]])
            return unless @@info_for_call_id[call_id]
            STDERR.puts "[MAIN] Got answer from thread for #{call_id}..."
            @@info_for_call_id[call_id][:notify][0].read_nonblock(1024)
            xml = StringIO.open do |io|
                io.puts "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                io.puts "<Response>"
                io.puts "<Gather maxDigits=\"4\" timeout=\"1500\" onData=\"https://hackschule.de/ivr/\">"
                io.puts "<Play>"
                io.puts "<Url>https://hackschule.de#{@@info_for_call_id[call_id][:last_path]}</Url>"
                io.puts "</Play>"
                io.puts "</Gather>"
                io.puts "</Response>"
                io.string
            end
            response.headers['Content-Type'] = 'application/xml'
            response.headers['Content-Length'] = "#{xml.size}"
            response.body = xml
        end
    end
end

