class DataStream:
    def __init__(self, bytes):
        self.bytes = bytes
        self.offset = 0
        self.len = len(self.bytes)
        
    def length(self):
        return self.len
    
    def next(self):
        if self.offset < self.len:
            b = self.bytes[self.offset]
            self.offset += 1
            return b
        else:
            raise RuntimeError('Keine weiteren Bytes vorhanden!')
        
    def eof(self):
        return self.offset >= self.len
    
    def reset(self):
        self.offset = 0
        
    def read(self):
        return self.bytes
