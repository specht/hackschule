#!/usr/bin/env ruby

require 'sinatra'
require 'json'
require 'yaml'

class Main < Sinatra::Base
    post '/ivr/' do
        form = request.body.read
        decoded_form = URI.decode_www_form(form)
        data = Hash[decoded_form]
        STDERR.puts data.to_yaml
        # TODO: user xcid
        call_id = data['callId']
        event = data['event']
        if event == 'newCall'
            STDERR.puts "NEW CALL!"
            xml = StringIO.open do |io|
                io.puts "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
                io.puts "<Response>"
                io.puts "<Gather maxDigits=\"1\" timeout=\"5000\" onData=\"https://hackschule.de/ivr/\">"
                io.puts "<Play>"
                io.puts "<Url>https://hackschule.de/tts/ef/c8184c89dc45f5.wav</Url>"
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
