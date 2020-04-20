# Types of tasks

## #1 Checking stdout (`type = check_stdout`)

- record stdout
- define a Proc which checks the stdout contents with Ruby code

    [check_stdout]
    Proc.new do |stdout|
        temp = stdout.downcase
        ['hello', 'world', '!'].all? { |w| temp.include?(w) }
    end

## #2 Checking stdin/stdout pairs (`type = check_stdout`)

- define pairs of stdin/stdout
- define a Hash of stdin => Proc to check stdout with Ruby code

    [check_stdout]
    checks = {}
    input = 'blablabla'
    checks[input] = Proc.new do |result|
        result.include?(input)
    end
    checks
    
## #3 Implement a method (`type = method`)

- define a method name
- define n named, typed arguments plus a return type
  - possible types: int, float, string, char, bool, list (also nested), dict
  - if some types are not implemented for a language, that task can't be solved in that language
  - only for OOP languages
- define return type
- define pairs of expected output (one value) / input (n values) with Ruby code
- possible to disable functions (language specific)

Python template:

    class Task:
        def maximum(self, zahlen):
            # Ersetze 'pass' durch deine Lösung
            pass

Ruby template:

    class Task
        def maximum(zahlen)
            # Schreibe deine Lösung hier rein
        end
    end
    
C++ template:

    int Task::maximum(std::list<int> zahlen) 
    {
        // Schreibe deine Lösung hier rein
    }
    
## #4 API (`type = api`)

- define an API
- implement that API in Ruby
- provide a thin layer via pipe for every language
