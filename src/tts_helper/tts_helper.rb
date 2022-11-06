#!/usr/bin/env ruby

require 'cgi'
require 'digest'
require 'fileutils'
require 'sinatra'
require 'yaml'
require 'neo4j_bolt'

Neo4jBolt.bolt_host = 'neo4j'
Neo4jBolt.bolt_port = 7687

def split_sentences(s)
    s.gsub(/\s+/, ' ').strip.split(/([^\d][\.\?!]+)/).each_slice(2).map { |x| x.map { |y| y.strip }.join('').strip }
end

class Main < Sinatra::Base
    include Neo4jBolt

    get '/ping' do
        content_type 'text/plain'
        'hello there'
    end

    def render_sound(command)
        sha1 = Digest::SHA1.hexdigest(command)[0, 16]
        path = "/tts/#{sha1[0, 2]}/#{sha1[2, sha1.size - 2]}.wav"
        unless File.exists?(path)
            FileUtils::mkpath(File.dirname(path))
            patched_command = command.gsub('__OUT_PATH__', path)
            STDERR.puts patched_command
            system(patched_command)
            unless File.exists?(path)
                raise "command failed!"
            end
        end
        path
    end

    post '/' do
        body =request.body.read
        data = JSON.parse(body)
        response = {}

        if data['command'] == 'say'
            STDERR.puts ">>> SAY: #{data.to_json}"
            sentence = data['s'].strip
            remaining = []
            unless data['already_split'] == true
                sentences = split_sentences(sentence)
                sentence = sentences.shift
                remaining = sentences
                response[:remaining] = remaining
            end
            STDERR.puts "[#{sentence}]"
            if data['title'] && data['email']
                sentence_sha1 = Digest::SHA1.hexdigest(sentence)[0, 12]
                STDERR.puts ">>> SENTENCE SHA1: #{sentence_sha1}"
                rows = neo4j_query(<<~END_OF_QUERY, {:email => data['email'], :sentence_sha1 => sentence_sha1, :title => data['title']}) do |row|
                    MATCH (u:User {email: $email})-[:RECORDED]->(r:Recording)-[:FOR]->(s:Sentence {sha1: $sentence_sha1})-[:FOR]->(t:Title {title: $title})
                    RETURN r.sha1 AS sha1 LIMIT 1;
                END_OF_QUERY
                    temp_path = "/tts/#{row['sha1'][0, 2]}/#{row['sha1'][2, row['sha1'].size - 2]}.wav"
                    if File.exists?(temp_path)
                        response[:path] = temp_path
                    end
                end
            end
            response[:path] ||= render_sound("curl -s -o \"__OUT_PATH__\" http://tts:5002/api/tts?text=#{CGI.escape(sentence)}")
        elsif data['command'] == 'play'
            temp_path = render_sound("cd /tts && yt-dlp -x --audio-format wav -o \"temp.%(ext)s\" \"#{data['url']}\" && ffmpeg -i \"temp.wav\" -ar 22050 -ac 1 \"__OUT_PATH__\" && rm temp.wav")
            response[:path] = render_sound("ffmpeg -ss #{data['offset'] / 1000.0} -t #{data['length'] / 1000} -i \"#{temp_path}\" \"__OUT_PATH__\"")
        elsif data['command'] == 'say_get_missing_sha1'
            result = []
            data['sentences'].each do |sentence|
                command = "curl -s -o \"__OUT_PATH__\" http://tts:5002/api/tts?text=#{CGI.escape(sentence)}"
                sha1 = Digest::SHA1.hexdigest(command)[0, 16]
                path = "/tts/#{sha1[0, 2]}/#{sha1[2, sha1.size - 2]}.wav"
                unless File.exists?(path)
                    result << sentence
                end
            end
            response[:missing_sentences] = result
        elsif data['command'] == 'sleep'
            ms = data['ms']
            # TODO: assert that ms is an int within a range
            ms = 0 if ms < 0
            ms = 60 * 1000 if ms > 60 * 1000
            response[:path] = render_sound("sox -n -r 22050 -b 16 \"__OUT_PATH__\" synth #{ms/1000.0} brownnoise vol -60dB")
        elsif data['command'] == 'mix'
            voice_path = render_sound("sox #{data['voice_queue'].map { |x| '"' + x + '"'}.join(' ')} \"__OUT_PATH__\"")
            response[:path] = voice_path
            if data['bg_tag']
                bg_path = render_sound("cd /tts && yt-dlp -x --audio-format wav -o \"temp.%(ext)s\" \"#{data['bg_tag']}\" && ffmpeg -i \"temp.wav\" -ar 22050 -ac 1 \"__OUT_PATH__\" && rm temp.wav")
                response[:path] = bg_path
                duration = `ffprobe -show_entries format=duration -of default=nk=1:nw=1 \"#{voice_path}\" 2>/dev/null`.to_f
                ducking = data['bg_ducking'].to_f
                ducking = 0.0 if ducking < 0.0
                ducking = 1.0 if ducking > 1.0
                mix_path = render_sound("ffmpeg -ss #{data['bg_offset'] / 1000.0} -i \"#{bg_path}\" -i \"#{voice_path}\" -filter_complex \"[1]asplit=2[sc][id]; [0][sc]sidechaincompress=threshold=0.00098:ratio=5:makeup=1:level_sc=0.5:release=400:mix=#{ducking},afade=t=in:ss=0:d=0.5[compr]; [compr][id]amix=inputs=2:duration=first,afade=t=out:st=#{duration-1.0}:d=1\" \"__OUT_PATH__\"")
                response[:path] = mix_path
            end
        end
        if response[:path]
            response[:path_hd] = response[:path]
            low_khz_path = render_sound("sox \"#{response[:path]}\" -r 8000 -c 1 \"__OUT_PATH__\"")
            response[:path] = low_khz_path
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
