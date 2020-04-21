class Runner
    def initialize(script, language, sandbox_dir, task)
        @script = script
        @language = language
        @sandbox_dir = sandbox_dir
        @task = task
        @script_path = File.join(@sandbox_dir, "main#{LANGUAGE_FILE_EXTENSIONS[@language]}")
        
        # clear sandbox directory
        FileUtils.rm_rf(@sandbox_dir)
        FileUtils.mkpath(@sandbox_dir)
    end
    
    def handle_stdout(s)
    end
    
    def launch()
        raise 'override me!'
    end
    
    def verify()
        raise 'override me!'
    end
end
