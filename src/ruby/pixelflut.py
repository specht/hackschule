import json
import urllib.request

import os
os.environ = {}

class Pixelflut:
    def __init__(self, pipe):
        self.pipe = pipe
        self.queue = []
        self._drawn_something = False
        
    def flush_queue(self):
        #urllib.request.urlopen(f'http://pixelflut:9292/pixelflut/d')
        req = urllib.request.Request(url = 'http://pixelflut:9292/pixelflut/d',
                                     data = str.join("\n", self.queue).encode(),
                                     headers = {},
                                     method = 'POST')
        with urllib.request.urlopen(req) as res:
            pass
        self.queue = []

    def set_pixel(self, x, y, r, g, b):
        x = int(x)
        y = int(y)
        if x >= 0 and x < 256 and y >= 0 and y < 144:
            r = min(max(int(r), 0), 255)
            g = min(max(int(g), 0), 255)
            b = min(max(int(b), 0), 255)
            self.queue.append(f'{x}/{y}/{r}/{g}/{b}')
            self._drawn_something = True
            if len(self.queue) > 1000:
                self.flush_queue()

    def finalize(self):
        if len(self.queue) > 0:
            self.flush_queue()
        urllib.request.urlopen(f'http://pixelflut:9292/pixelflut/s')
        if self._drawn_something:
            self.pipe.write(json.dumps({'status': 'passed'}) + "\n")
            self.pipe.flush()
            
