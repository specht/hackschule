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

class Demon:
    def __init__(self, x, y, dir):
        self.x = x
        self.y = y
        self.dir = dir

class Wizard:
    def __init__(self, pipe, map, hero, demons):
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
        self.demons = []
        for demon in demons:
            self.demons.append(Demon(demon['x'], demon['y'], demon['dir']))
        
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
    
    def spread_gradient(self, gradient_map, x, y, d):
        if (gradient_map[y][x] == '.') or (type(gradient_map[y][x]) == int and (d < gradient_map[y][x])):
            gradient_map[y][x] = d
            if x > 0:
                self.spread_gradient(gradient_map, x - 1, y, d + 1)
            if y > 0:
                self.spread_gradient(gradient_map, x, y - 1, d + 1)
            if x < self.width - 1:
                self.spread_gradient(gradient_map, x + 1, y, d + 1)
            if y < self.height - 1:
                self.spread_gradient(gradient_map, x, y + 1, d + 1)
    
    def move_demons(self):
        gradient_map = []
        for y in range(self.height):
            gradient_map.append([])
            for x in range(self.width):
                m = self.read_map(x, y)
                c = '.'
                if 'lwbrULRWfdCz'.find(m) > -1:
                    c = 'X'
                gradient_map[-1].append(c)
        self.spread_gradient(gradient_map, self.hero.x, self.hero.y, 0)
        #for y in range(self.height):
            #for x in range(self.width):
                #print(f"{gradient_map[y][x]:3}", end = '')
            #print()
        #print()
        delta = []
        for demon in self.demons:
            best_d = None
            best_score = None
            for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
                tx = demon.x + d[0]
                ty = demon.y + d[1]
                if tx >= 0 and tx < self.width and ty >= 0 and ty < self.height and type(gradient_map[ty][tx]) == int:
                    if best_d != None:
                        if gradient_map[ty][tx] > best_score:
                            continue
                    best_d = d
                    best_score = gradient_map[ty][tx]
            if best_d != None: 
                delta.append({'x': best_d[0], 'y': best_d[1]})
            else:
                delta.append({'x': 0, 'y': 0})
        self.pipe.write(json.dumps({'command': 'move_demons', 'demons': delta}) + "\n")
        self.pipe.flush()
        for i, demon in enumerate(self.demons):
            demon.x += delta[i]['x']
            demon.y += delta[i]['y']
            if demon.x == self.hero.x and demon.y == self.hero.y:
                self.pipe.write(json.dumps({'command': 'eaten_alive'}) + "\n")
                self.pipe.flush()
                raise WizardException("Autsch, du wurdest von einem Monster gefressen!")
        
    def forward(self):
        delta = self.peek_forward()
        nx = self.hero.x + delta[0]
        ny = self.hero.y + delta[1]
        # check for walls
        if self.map_is(nx, ny, 'd') or self.map_is(nx + 1, ny, 'd'):
            raise WizardException("Autsch, du bist gegen eine Tür gerannt!")
        if self.map_is(nx, ny, 'lwbrULRWf') or nx < 0 or ny < 0 or nx >= self.width or ny >= self.height:
            raise WizardException("Autsch, du bist in eine Wand gerannt!")
        if self.map_is(nx, ny, 'C'):
            raise WizardException("Autsch, du bist in eine Säule gerannt!")
        if self.map_is(nx, ny, 'z'):
            raise WizardException("Autsch, du bist gegen eine Truhe gerannt!")

        self.pipe.write(json.dumps({'command': 'forward', 'sleep': self.delay}) + "\n")
        self.pipe.flush()
        self.hero.x = nx
        self.hero.y = ny
        for i, demon in enumerate(self.demons):
            if demon.x == self.hero.x and demon.y == self.hero.y:
                self.pipe.write(json.dumps({'command': 'eaten_alive'}) + "\n")
                self.pipe.flush()
                raise WizardException("Autsch, du wurdest von einem Monster gefressen!")
        self.move_demons()
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

    def coin_here(self):
        return self.map_is(self.hero.x, self.hero.y, 'c')
            
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
