from inspect import getmembers, isfunction
import os
import sys
import random
from unittest.mock import patch

USE_TASK_CLASS = #{USE_TASK_CLASS}

#{DISABLE_OS_FUNCTIONS}

random.seed(0)

class TestException(Exception):
    def __init__(self, received, data, expected):
        self.received = received
        self.data = data
        self.expected = expected
    
    def report(self):
        sys.stderr.write('\u001b[44;1m[ Hinweis ]\u001b[0m ')
        sys.stderr.flush()
        sys.stderr.write("Dein Programm ist leider noch nicht korrekt, da es ein falsches Ergebnis berechnet hat.\n")
        sys.stderr.write(f'Eingabe : {self.data}\n')
        sys.stderr.write(f'Erwartet: {self.expected}\n')
        sys.stderr.write(f'Bekommen: {self.received}\n')
        #sys.exit(1)                                

def assert_equal(received, data, expected):
    if received != expected:
        raise TestException(received, data, expected)
        
_test_cases = []
        
def add_input(input, expected_result):
    _test_cases.append([input, expected_result])
    
def DISABLE_FUNCTION(*argv):
    pass
    
#{INPUT}

#{IMPORTS}
from main import *

#{DISABLE_FUNCTIONS}
def run_tests():
    try:
        task = Task()
        for i, data in enumerate(_test_cases):
            sys.stderr.write("\r\u001b[44;1m[ Test ]\u001b[0m ")
            sys.stderr.write(f"Durchlauf {i + 1} von {len(_test_cases)}...")
            assert_equal(task.#{THE_FUNCTION_NAME}(data[0]), data[0], data[1])
        sys.stderr.write(" ok.\r\n")
    except TestException as e:
        sys.stderr.write(" fehlgeschlagen.\r\n\r\n")
        e.report()
        sys.exit(1)

if USE_TASK_CLASS:
    run_tests()
