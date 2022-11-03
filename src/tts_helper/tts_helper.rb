#!/usr/bin/env ruby

require 'sinatra'
require 'yaml'

class Main < Sinatra::Base
    get '/ping/' do
        content_type 'text/plain'
        'hello there'
    end
end
