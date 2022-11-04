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
            sentence = data['s'].strip
            remaining = []
            unless data['already_split'] == true
                sentences = sentence.split(/([^\d][\.\?!]+)/).each_slice(2).map { |x| x.map { |y| y.strip }.join('').strip }
                sentence = sentences.shift
                remaining = sentences
                response[:remaining] = remaining
            end
            response[:path] = render_sound("curl -s -o \"__OUT_PATH__\" http://tts:5002/api/tts?text=#{CGI.escape(sentence)}")
        elsif data['command'] == 'sleep'
            ms = data['ms']
            # TODO: assert that ms is an int within a range
            response[:path] = render_sound("sox -n -r 22050 -b 16 \"__OUT_PATH__\" synth #{ms/1000.0} brownnoise vol -60dB")
        elsif data['command'] == 'mix'
            voice_path = render_sound("sox #{data['voice_queue'].map { |x| '"' + x + '"'}.join(' ')} \"__OUT_PATH__\"")
            response[:path] = voice_path
            if data['bg_tag']
                bg_path = render_sound("cd /tts && yt-dlp -x --audio-format wav -o \"temp.%(ext)s\" \"#{data['bg_tag']}\" && ffmpeg -i \"temp.wav\" -ar 22050 -ac 1 \"__OUT_PATH__\" && rm temp.wav")
                response[:path] = bg_path
                duration = `ffprobe -show_entries format=duration -of default=nk=1:nw=1 \"#{voice_path}\" 2>/dev/null`.to_f
                mix_path = render_sound("ffmpeg -i \"#{bg_path}\" -i \"#{voice_path}\" -filter_complex \"[1]asplit=2[sc][id]; [0][sc]sidechaincompress=threshold=0.00098:ratio=5.0:makeup=1:level_sc=0.5:release=400:mix=0.95[compr]; [compr][id]amix=inputs=2:duration=first,afade=t=out:st=#{duration-1.0}:d=1\" \"__OUT_PATH__\"")
                response[:path] = mix_path
            end
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
