#!/usr/bin/env ruby

require 'chunky_png'
require 'json'
require 'yaml'
require 'zlib'

def encode_4bit(data)
    out = []
    i = 0
    while i < data.size
        p0 = data[i]
        i += 1
        p1 = data[i]
        i += 1
        out << ((p1 & 15) << 4 | (p0 & 15))
    end
    out
end

def decode_4bit(data)
    out = []
    i = 0
    data.each do |b|
        out << (b & 15)
        out << ((b >> 4) & 15)
    end
    out
end

def encode_rle(data)
    out = []
    i = 0
    while i < data.size
        count = 0
        k = i
        while data[k] == data[i] && count < 255 do
            count += 1
            k += 1
        end
        out << count
        out << data[i]
        i = k
    end
    out
end

def decode_rle(data)
    out = []
    i = 0
    while i < data.size
        count = data[i]
        i += 1
        color = data[i]
        i += 1
        count.times { out << color }
    end
    out
end

def encode_rle2(data)
    out = []
    i = 0
    while i < data.size
        count = 0
        k = i
        while data[k] == data[i] && count < 127 do
            count += 1
            k += 1
        end
        if count > 1
            out << (count | 0x80)
            out << data[i]
        else
            out << data[i]
        end
        i = k
    end
    out
end

def decode_rle2(data)
    out = []
    i = 0
    while i < data.size do
        b = data[i]
        i += 1
        if b > 127
            count = b - 128
            b = data[i]
            i += 1
            count.times { out << b }
        else
            out << b
        end
    end
    out
end

def encode_rle3(data)
    out = []
    i = 0
    while i < data.size
        count = 0
        k = i
        while data[k] == data[i] && count < 16 do
            count += 1
            k += 1
        end
        out << (((count - 1) << 4) | (data[i] & 15))
        i = k
    end
    out
end

def decode_rle3(data)
    out = []
    i = 0
    data.each do |b|
        count = (b >> 4) + 1
        color = (b & 15)
        count.times { out << color }
    end
    out
end

def encode_deflate(data)
    zd = Zlib::Deflate.new()
    zd.deflate(data.pack('C*'), Zlib::FINISH).unpack('C*')
end

def decode_deflate(data)
    zi = Zlib::Inflate.new
    zi.inflate(data.pack('C*')).unpack('C*')
end

(0..5).each do |i|
    data = {}
    path = "p#{i}.png"
    STDERR.puts path
    image = ChunkyPNG::Image.from_blob(File.read(path))
    data[:width] = image.width
    data[:height] = image.height
    data[:palette] = image.palette.to_a
    data[:raw] = []
    palette = image.palette.to_a
    image.pixels.each do |color|
        index = palette.index(color)
        data[:raw] << index
    end
    verify = []
    algo = 'raw'
    if i == 0
        data[:encoded] = data[:raw].dup
        verify = data[:encoded]
    elsif i == 1
        algo = '4bit'
        data[:encoded] = encode_4bit(data[:raw])
        verify = decode_4bit(data[:encoded])
    elsif i == 2
        algo = 'rle'
        data[:encoded] = encode_rle(data[:raw])
        verify = decode_rle(data[:encoded])
    elsif i == 3
        algo = 'rle2'
        data[:encoded] = encode_rle2(data[:raw])
        verify = decode_rle2(data[:encoded])
    elsif i == 4
        algo = 'rle3'
        data[:encoded] = encode_rle3(data[:raw])
        verify = decode_rle3(data[:encoded])
    elsif i == 5
        algo = 'deflate'
        data[:encoded] = encode_deflate(data[:raw])
        verify = decode_deflate(data[:encoded])
    end
    STDERR.puts "Bytes: #{data[:encoded].size} (#{sprintf('%d', data[:encoded].size * 100 / (data[:width] * data[:height]))}%) / compressed with #{algo}"
    data[:palette].map! do |x|
        sprintf('#%02x%02x%02x', (x >> 24) & 0xff, (x >> 16) & 0xff, (x >> 8) & 0xff)
    end
    STDERR.puts "ERROR decoding image!" if data[:raw] != verify
    STDERR.puts '-' * 40
    File.open("#{path}.json", 'w') { |f| f.write(data.to_json) }
end
