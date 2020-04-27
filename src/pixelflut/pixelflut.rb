#!/usr/bin/env ruby

require 'sinatra'
require 'chunky_png'
require 'yaml'

$png = ChunkyPNG::Image.from_datastream(ChunkyPNG::Datastream.from_file('pixelflut_empty.png'))
begin
    $png = ChunkyPNG::Image.from_datastream(ChunkyPNG::Datastream.from_file('/raw/pixelflut.png'))
rescue
end

$png_stream = nil

class Main < Sinatra::Base
    get '/pixelflut/' do
        content_type 'image/png'
        $png_stream ||= $png.to_datastream().to_blob()
    end

    get '/pixelflut/_reset_canvas' do
        $png = ChunkyPNG::Image.from_datastream(ChunkyPNG::Datastream.from_file('pixelflut_empty.png'))
        $png_stream = nil
        'ok'
    end

    get '/pixelflut/s' do
        content_type 'image/png'
        File.open('/raw/pixelflut.png', 'w') do |f|
            f.write($png.to_datastream().to_blob())
        end
        'ok'
    end

    post '/pixelflut/d' do
        request.body.read.each_line do |line|
            next unless line =~ /^\d+\/\d+\/\d+\/\d+\/\d+$/
            params = line.split('/').map { |x| x.to_i }
            x = params[0]
            y = params[1]
            r = params[2]
            g = params[3]
            b = params[4]
            x = [[0, x].max, 255].min
            y = [[0, y].max, 143].min
            r = [[0, r].max, 255].min
            g = [[0, g].max, 255].min
            b = [[0, b].max, 255].min
            $png[x,y] = ChunkyPNG::Color.rgb(r, g, b)
        end
        $png_stream = nil
        'ok'
    end
end
