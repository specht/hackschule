import json
import time
import sys

class WizardException(Exception):
    def __init__(self, message):
        self.message = message
        
class Hero:
    def __init__(self, x, y, dir):
        self.x = x
        self.y = y
        self.dir = dir

class Wizard:
    def __init__(self, pipe, map, hero):
        self.pipe = pipe
        self.delay = 0.25
        self.map = []
        for row in map:
            line = []
            for c in row:
                line.append(c)
            self.map.append(line)
        self.width = len(self.map[0])
        self.height = len(self.map)
        self.hero = Hero(hero['x'], hero['y'], hero['dir'])
        self.__coins = 0
        self.__init__func__ = None
        self.__verify__func__ = None
        
    def use_init(self, f):
        self.__init__func__ = f
        
    def use_verify(self, f):
        self.__verify__func__ = f
        
    def run_it(self):
        try:
            if self.__init__func__ != None:
                self.__init__func__(self)
            self.run()
            passed = False
            if self.__verify__func__ != None:
                passed = self.__verify__func__(self)
            if passed:
                self.pipe.write(json.dumps({'status': 'passed'}) + "\n")
                self.pipe.flush()
        except WizardException as e:
            sys.stderr.write('\u001b[44;1m[ Fehler ]\u001b[0m ' + e.message + '\n')
            sys.exit(1)
    
    def peek_forward(self):
        if self.hero.dir == 0:
            return [1, 0]
        elif self.hero.dir == 1:
            return [0, 1]
        elif self.hero.dir == 2:
            return [-1, 0]
        elif self.hero.dir == 3:
            return [0, -1]
        
    def read_map(self, x, y):
        if x >= 0 and x < self.width and y >= 0 and y < self.height:
            return self.map[y][x]
        else:
            return '?'

    def map_is(self, x, y, c):
        return self.read_map(x, y) in c
        
    def forward(self):
        delta = self.peek_forward()
        nx = self.hero.x + delta[0]
        ny = self.hero.y + delta[1]
        # check for walls
        if self.map_is(nx, ny, 'd') or self.map_is(nx + 1, ny, 'd'):
            raise WizardException("Autsch, du bist gegen eine Tür gerannt!")
        if self.map_is(nx, ny, 'lwbrULRW') or nx < 0 or ny < 0 or nx >= self.width or ny >= self.height:
            raise WizardException("Autsch, du bist in eine Wand gerannt!")
        if self.map_is(nx, ny, 'C'):
            raise WizardException("Autsch, du bist in eine Säule gerannt!")
        if self.map_is(nx, ny, 'z'):
            raise WizardException("Autsch, du bist gegen eine Truhe gerannt!")

        self.pipe.write(json.dumps({'command': 'forward'}) + "\n")
        self.pipe.flush()
        self.hero.x = nx
        self.hero.y = ny
        self.pipe.write(json.dumps({'command': 'sleep', 'sleep': self.delay}) + "\n")
        self.pipe.flush()
        time.sleep(self.delay)
        
    def turn_left(self):
        self.hero.dir = (self.hero.dir + 3) % 4
        self.pipe.write(json.dumps({'command': 'turn_left'}) + "\n")
        self.pipe.flush()

    def turn_right(self):
        self.hero.dir = (self.hero.dir + 1) % 4
        self.pipe.write(json.dumps({'command': 'turn_right'}) + "\n")
        self.pipe.flush()
        
    def say(self, message):
        self.pipe.write(json.dumps({'command': 'say', 'message': message}) + "\n")
        self.pipe.flush()
        time.sleep(len(message) * 0.1)

    def wait(self, delay):
        self.pipe.write(json.dumps({'command': 'sleep', 'sleep': delay}) + "\n")
        self.pipe.flush()
        time.sleep(delay)

    def get_coin(self):
        # check for coins
        if self.map_is(self.hero.x, self.hero.y, 'c'):
            self.map[self.hero.y][self.hero.x] = ' '
            self.pipe.write(json.dumps({'command': 'take_coin', 'x': self.hero.x, 'y': self.hero.y}) + "\n")
            self.pipe.flush()
            self.__coins += 1
        else:
            raise WizardException("Du hast versucht, eine Münze zu nehmen, obwohl hier keine Münze liegt.")
        
    def coins(self):
        return self.__coins

    def drop_coin(self):
        pass

    def coins_carried(self):
        return 0

    def coins_capacity(self):
        return 0

    def set_speed(self, speed):
        if speed < 1:
            speed = 1
        if speed > 100:
            speed = 100
        self.delay = pow((speed / 100.0) - 1.0, 2.0)
