class ScriptTypeCheckStdout < ScriptType
    def initialize(script)
        super(script)
    end
    
    def launch()
        raise 'override me!'
    end
    
    def verify()
        raise 'override me!'
    end
end
