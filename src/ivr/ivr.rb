#!/usr/bin/env ruby

require 'sinatra'
require 'json'
require 'yaml'
require 'open3'

DEFAULT_SCRIPT = 'mp0lx174'

class Main < Sinatra::Base
    def self.launch_script(call_id, tag)
        STDERR.puts "Launching script #{tag}..."
        path = "/tmp/script-#{call_id}.py"
        File.open(path, 'w') do |f|
            script = File.read("/code/#{tag}.py")
            f.puts(@@header)
            f.puts(script)
            f.puts "game = Game(sys.stdout)"
            f.puts "game.run()"
            f.puts "game.hangup()"
        end
        stdin, stdout, stderr, thread = Open3.popen3('python3', path, '--ivr')
        {:stdin => stdin, :stdout=> stdout, :stderr => stderr, :thread => thread}
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
        @@info_for_call_id = {}
        @@watcher_ping = IO.pipe
        @@call_id_for_stdout_fd = {}
        Thread.new do
            STDERR.puts "I'm a watcher!"
            loop do
                read_sockets = []
                read_sockets << @@watcher_ping[0]
                @@info_for_call_id.each_pair do |call_id, info|
                    read_sockets << info[:stdout]
                end
                STDERR.puts "Waiting on #{read_sockets.size} sockets"
                streams = IO.select(read_sockets)
                STDERR.puts "Got something"
                streams.first.each do |io|
                    call_id = @@call_id_for_stdout_fd[io.fileno]
                    if call_id
                        STDERR.puts "Got a response for #{call_id}!"
                    end
                end
                sleep 1.0
            end
        end
    end

    post '/ivr/' do
        form = request.body.read
        decoded_form = URI.decode_www_form(form)
        data = Hash[decoded_form]
        STDERR.puts data.to_yaml
        call_id = data['callId']
        event = data['event']
        if event == 'newCall'
            STDERR.puts "NEW CALL with call id #{call_id}!"
            @@info_for_call_id[call_id] = self.class.launch_script(call_id, DEFAULT_SCRIPT)
            @@info_for_call_id[call_id][:last_path] = nil
            @@call_id_for_stdout_fd[@@info_for_call_id[call_id][:stdout].fileno] = call_id
            @@watcher_ping[1].puts("hey")
            # xml = StringIO.open do |io|
            #     io.puts "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            #     io.puts "<Response>"
            #     io.puts "<Gather maxDigits=\"4\" timeout=\"3000\" onData=\"https://hackschule.de/ivr/\">"
            #     io.puts "<Play>"
            #     io.puts "<Url>https://hackschule.de/tts/a4/c4dad1efbfe633.wav</Url>"
            #     io.puts "</Play>"
            #     io.puts "</Gather>"
            #     io.puts "</Response>"
            #     io.string
            # end
            # response.headers['Content-Type'] = 'application/xml'
            # response.headers['Content-Length'] = "#{xml.size}"
            # response.body = xml
        elsif event == 'dtmf'
            dtmf = data['dtmf']
        end
    end
end

