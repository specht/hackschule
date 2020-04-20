class ScriptType
    def initialize(script)
        @script = script
    end
    
    def launch()
        raise 'override me!'
    end
    
    def verify()
        raise 'override me!'
    end
end
