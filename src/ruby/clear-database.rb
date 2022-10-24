#!/usr/bin/env ruby
require './neo4j.rb'

class ClearDatabase
    include QtsNeo4j
    
    def run
        transaction do
            neo4j_query('MATCH (n) DETACH DELETE n;')
        end
    end
end

script = ClearDatabase.new
script.run
