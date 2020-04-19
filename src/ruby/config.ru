require 'faye'
Faye::WebSocket.load_adapter('thin')
require File.expand_path('main', File.dirname(__FILE__))

use Faye::RackAdapter, :mount => '/faye', :timeout => 25
run Main
