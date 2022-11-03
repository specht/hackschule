#!/usr/bin/env ruby

require 'cgi'
require 'digest'
require 'fileutils'
require 'sinatra'
require 'yaml'

class Main < Sinatra::Base
    get '/ping' do
        content_type 'text/plain'
        'hello there'
    end

    post '/' do
        body =request.body.read
        STDERR.puts "BODY: [#{body}]"
        data = JSON.parse(body)
        STDERR.puts "DATA: #{data.to_yaml}"
        response = {}

        if data['command'] == 'say'
            text = data['s'].strip
            sha1 = Digest::SHA1.hexdigest(text)[0, 10]
            STDERR.puts "[#{sha1}] #{text}"
            path = "/tts/thorsten/#{sha1[0, 2]}/#{sha1[2, sha1.size - 2]}.wav"
            unless File.exists?(path)
                FileUtils::mkpath(File.dirname(path))
                command = "curl -s -o \"#{path}\" http://tts:5002/api/tts?text=#{CGI.escape(text)}"
                system(command)
            end
            response[:sha1] = sha1
        elsif data['command'] == 'sleep'
            ms = data['ms']
            # TODO: assert that ms is an int within a range
            path = "/tts/silence/#{ms}.wav"
            unless File.exists?(path)
                command = "sox -n -r 22050 -b 16 \"#{path}\" synth #{ms/1000.0} brownnoise vol -60dB"
                STDERR.puts command
                system(command)
            end
        elsif data['command'] == 'mix'
            key = "#{data['voice_queue'].to_json}}"
            sha1 = Digest::SHA1.hexdigest(key)[0, 10]
            path = "/tts/mix/#{sha1[0, 2]}/#{sha1[2, sha1.size - 2]}.wav"
            unless File.exists?(path)
                FileUtils::mkpath(File.dirname(path))
                in_paths = []
                data['voice_queue'].each do |entry|
                    if entry['type'] == 'say'
                        sha1 = entry['sha1']
                        in_paths << "/tts/thorsten/#{sha1[0, 2]}/#{sha1[2, sha1.size - 2]}.wav"
                    elsif entry['type'] == 'sleep'
                        in_paths << "/tts/silence/#{entry['ms']}.wav"
                    end
                end
                command = "sox #{in_paths.map {|x| '"' + x + '"'}.join(' ')} \"#{path}\""
                STDERR.puts command
                system(command)
            end
            bg_path = "/tts/yt/#{data['bg_tag']}.wav"
            unless File.exists?(bg_path)
                command = "cd /tts/yt && youtube-dl -f 140 -x https://youtu.be/#{data['bg_tag']}"
                STDERR.puts command
                system(command)
                dl_path = Dir["/tts/yt/*#{data['bg_tag']}*"].first
                command = "ffmpeg -i \"#{dl_path}\" -ar 22050 -ac 1 -t 300 \"#{bg_path}\""
                STDERR.puts command
                system(command)
            end
            voice_path = path
            mix_path = voice_path
            if data['bg_tag']
                key = "#{data['bg_tag']}/#{data['voice_queue'].to_json}}"
                sha1 = Digest::SHA1.hexdigest(key)[0, 10]
                path = "/tts/mix/#{sha1[0, 2]}/#{sha1[2, sha1.size - 2]}.wav"
                unless File.exists?(path)
                    FileUtils::mkpath(File.dirname(path))
                    command = "ffmpeg -i \"#{bg_path}\" -i \"#{voice_path}\" -filter_complex \"[1]apad,adelay=100|100,aformat=sample_rates=22050:channel_layouts=stereo,asplit=2[sc][id]; [0][sc]sidechaincompress=threshold=0.00098:ratio=5.0:makeup=1:level_sc=0.5:release=400:mix=0.95[compr]; [compr][id]amix=inputs=2:duration=first\" \"#{path}\""
                    STDERR.puts command
                    system(command)
                end
                mix_path = path
            end
            response[:path_22k] = mix_path
            key = "8khz/#{data['bg_tag']}/#{data['voice_queue'].to_json}}"
            sha1 = Digest::SHA1.hexdigest(key)[0, 10]
            path = "/tts/mix/#{sha1[0, 2]}/#{sha1[2, sha1.size - 2]}.wav"
            unless File.exists?(path)
                FileUtils::mkpath(File.dirname(path))
                command = "sox \"#{mix_path}\" -r 8000 -c 1 \"#{path}\""
                STDERR.puts command
                system(command)
            end
            response[:path] = path
            STDERR.puts path
        end

        content_type = 'application/json'
        response.to_json

    end
end

# self.bg_play('C23E5grsczE')
# self.sleep(6000)
# self.say("Hallo und herzlich willkommen in der Hackschule.")
# self.sleep(2000)
# self.say("Leider können wir deinen Anruf momentan nicht persönlich entgegennehmen.")
# self.sleep(2000)
# self.say("Bitte gib deinen vierstelligen Code ein, um ein Spiel zu starten.")
# self.sleep(2000)
# self.say("Falls du keinen Code hast, kannst du auch ein zufälliges Spiel starten. Drücke dafür bitte einfach die 0.")
# self.hangup()
