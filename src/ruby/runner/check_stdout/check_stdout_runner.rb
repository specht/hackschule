class CheckStdoutRunner < Runner
    def initialize(script, language, sandbox_dir, task)
        super(script, language, sandbox_dir, task)
        return nil unless [:ruby, :python, :cpp].include?(@language)
        File.open(@script_path, 'w') do |f|
            f.write(@script)
        end
        @stdout_buffer = ''
        @verify = eval(@task[:check_stdout])
        @record_stdout = @verify.is_a? Proc
    end
    
    def launch()
        command = nil
        script_path_sandbox = @script_path.sub('/raw', '')
        if @language == :ruby
            command = ['docker', 'exec', '-i', SANDBOX, "timeout", SCRIPT_TIMEOUT.to_s, 
                       'ruby', script_path_sandbox]
        elsif @language == :python
            command = ['docker', 'exec', '-i', SANDBOX, 
                        "timeout", SCRIPT_TIMEOUT.to_s, 'python3', '-B', 
                        '-u', script_path_sandbox]
        elsif @language == :cpp
            binary_path_sandbox = script_path_sandbox.sub('.cpp', '')
            bash_script_path = @script_path.sub('.cpp', '.sh')
            bash_script_path_sandbox = script_path_sandbox.sub('.cpp', '.sh')
            File.open(bash_script_path, 'w') do |f|
                f.puts "gcc -o #{binary_path_sandbox} #{script_path_sandbox} && #{binary_path_sandbox}"
            end
            
            command = ['docker', 'exec', '-i', SANDBOX, 
                        "timeout", SCRIPT_TIMEOUT.to_s, 'bash', bash_script_path_sandbox]
        end
        return Open3.popen3(*command)
    end
    
    def handle_stdout(s)
        @stdout_buffer += s if @record_stdout
    end
    
    def verify()
        if @verify.is_a? Proc
            return @verify.call(@stdout_buffer)
        elsif @verify.is_a? Hash
            # test series of inputs with procs
            ws.send({:stderr => "\r\n"}.to_json)
            all_tests_passed = true
            @verify.keys.each.with_index do |input, i|
                ws.send({:stderr => "\r\u001b[44;1m[ Test ]\u001b[0m "}.to_json)
                ws.send({:stderr => "Durchlauf #{i + 1} von #{@verify.size}..."}.to_json)
                
                
                test_stdin, test_stdout, test_stderr, test_thread = 
                        Open3.popen3('docker', 'exec', '-i', 
                                        SANDBOX, "timeout", 
                                        SCRIPT_TIMEOUT.to_s, 
                                        'python3', '-u', 
                                        script_path.sub('/raw', ''))
                test_stdin.write(input)
                test_stdin.close
                
                unless @verify[input].call(test_stdout.read)
                    all_tests_passed = false
                    ws.send({:stderr => " fehlgeschlagen.\r\n"}.to_json)
                    break
                end
            end
            if all_tests_passed
                ws.send({:stderr => " ok.\r\n"})
                return true
            end
            return false
        end
    end
end
