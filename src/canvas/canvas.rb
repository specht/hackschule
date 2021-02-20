#!/usr/bin/env ruby

require 'sinatra'
require 'chunky_png'
require 'json'
require 'yaml'

# $png = ChunkyPNG::Image.from_datastream(ChunkyPNG::Datastream.from_file('canvas_empty.png'))
$png = {}
$png_stream = {}

class Main < Sinatra::Base
    def coalesce_canvas(email)
        $png[email] ||= ChunkyPNG::Image.from_datastream(ChunkyPNG::Datastream.from_file('canvas_empty.png'))
    end
    
    get '/canvas/:email/' do
        email = params['email']
        coalesce_canvas(email)
        content_type 'image/png'
        $png_stream[email] ||= $png[email].to_datastream().to_blob()
    end

    get '/canvas/:email/_reset_canvas' do
        email = params['email']
        STDERR.puts "Resetting canvas for #{email}"
        $png[email] = ChunkyPNG::Image.from_datastream(ChunkyPNG::Datastream.from_file('canvas_empty.png'))
        $png_stream[email] = nil
        'ok'
    end

    post '/canvas/:email/d' do
        email = params['email']
        coalesce_canvas(email)
        request.body.read.each_line do |line|
            next unless line =~ /^\d+\/\d+\/\d+\/\d+\/\d+$/
            params = line.split('/').map { |x| x.to_i }
            x = params[0]
            y = params[1]
            r = params[2]
            g = params[3]
            b = params[4]
            x = [[0, x].max, 127].min
            y = [[0, y].max, 127].min
            r = [[0, r].max, 255].min
            g = [[0, g].max, 255].min
            b = [[0, b].max, 255].min
            $png[email][x,y] = ChunkyPNG::Color.rgb(r, g, b)
        end
        $png_stream[email] = nil
        'ok'
    end
end
