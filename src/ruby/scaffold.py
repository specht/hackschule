from inspect import getmembers, isfunction
import os
import sys
import random
from unittest.mock import patch

USE_TASK_CLASS = #{USE_TASK_CLASS}

#{DISABLE_OS_FUNCTIONS}

random.seed(0)

class TestException(Exception):
    def __init__(self, received, expected, *input):
        self.received = received
        self.expected = expected
        self.input = input[0] if len(input) == 1 else input
    
    def report(self):
        sys.stderr.write('\u001b[44;1m[ Hinweis ]\u001b[0m ')
        sys.stderr.flush()
        sys.stderr.write("Dein Programm ist leider noch nicht korrekt, da es ein falsches Ergebnis berechnet hat.\n")
        sys.stderr.write(f'Eingabe : {self.input}\n')
        sys.stderr.write(f'Erwartet: {self.expected}\n')
        sys.stderr.write(f'Bekommen: {self.received}\n')
        #sys.exit(1)                                

def assert_equal(received, expected, *input):
    if received != expected:
        raise TestException(received, expected, *input)
        
_test_cases = []
        
def add_input(expected_result, *input):
    _test_cases.append([expected_result, input])
    
def DISABLE_FUNCTION(*argv):
    pass
    
#{INPUT}

#{IMPORTS}
#{CUSTOM_PRE}
#{CUSTOM_IMPORT_MAIN}
#{CUSTOM_POST}

#{DISABLE_FUNCTIONS}
def run_tests():
    try:
        task = Task()
        for i, data in enumerate(_test_cases):
            sys.stderr.write("\r\u001b[44;1m[ Test ]\u001b[0m ")
            sys.stderr.write(f"Durchlauf {i + 1} von {len(_test_cases)}...\n")
            ret = task.#{THE_FUNCTION_NAME}(*data[1])
            assert_equal(ret, data[0], *data[1])
            sys.stderr.write(f'Eingabe : {data[1]}\n')
            sys.stderr.write(f'Erwartet: {data[0]}\n')
            sys.stderr.write(f'Bekommen: {ret}\n')
        sys.stderr.write(" ok.\r\n")
    except TestException as e:
        sys.stderr.write(" fehlgeschlagen.\r\n\r\n")
        e.report()
        sys.exit(1)

if USE_TASK_CLASS:
    run_tests()

