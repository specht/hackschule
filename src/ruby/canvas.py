import json
import urllib.request
from data_stream import *

import os
os.environ = {}

class Canvas:
    def __init__(self, pipe, email, width, height, palette, in_bytes, target_pixels):
        self.pipe = pipe
        self.email = email
        self.width = width
        self.height = height
        self.palette = [(int(x[1:3], 16), int(x[3:5], 16), int(x[5:7], 16)) for x in palette]
        self.in_data_stream = DataStream(in_bytes)
        self.target_pixels = target_pixels
        self.pixels = [0 for _ in range(width * height)]
        self.queue = []
        req = urllib.request.Request(url = 'http://canvas:9292/canvas/' + self.email + '/_reset_canvas', method = 'GET')
        with urllib.request.urlopen(req) as res:
            pass
        
    def flush_queue(self):
        req = urllib.request.Request(url = 'http://canvas:9292/canvas/' + self.email + '/d',
                                     data = str.join("\n", self.queue).encode(),
                                     headers = {},
                                     method = 'POST')
        with urllib.request.urlopen(req) as res:
            pass
        self.queue = []

    def set_pixel(self, x, y, color):
        x = int(x)
        y = int(y)
        if color < 0:
            color = 0
        if color >= len(self.palette):
            color = len(self.palette) - 1
        if x >= 0 and x < self.width and y >= 0 and y < self.height:
            self.pixels[y * self.width + x] = color
            color = self.palette[color]
            self.queue.append(f'{x}/{y}/{color[0]}/{color[1]}/{color[2]}')
            if len(self.queue) > 1000:
                self.flush_queue()

    def finalize(self):
        if len(self.queue) > 0:
            self.flush_queue()
        if self.pixels == self.target_pixels:
            self.pipe.write(json.dumps({'status': 'passed'}) + "\n")
            self.pipe.flush()
            
