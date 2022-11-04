#!/usr/bin/env ruby

require 'sinatra'
require 'json'
require 'yaml'

class Main < Sinatra::Base
    get '*' do
        STDERR.puts request.path
    end
end
