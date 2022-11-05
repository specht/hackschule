import ast
import sys
import re
import json

class Analyzer(ast.NodeVisitor):
    def __init__(self):
        self.title = None
        self.sentences = []
        self.sentences_set = set([])

    def _parse_arg(self, x):
        if type(x) == ast.Constant:
            return x.value
        elif type(x) == ast.JoinedStr:
            return ''.join([self._parse_arg(y) for y in x.values])
        elif type(x) == ast.FormattedValue:
            return self._parse_arg(x.value)
        elif type(x) == ast.Name:
            # raise NonConstSentenceError()
            return f"[[[{x.id}]]]"
        elif type(x) == ast.BinOp:
            l = self._parse_arg(x.left)
            r = self._parse_arg(x.right)
            if isinstance(x.op, ast.Add):
                return l + r
            elif isinstance(x.op, ast.Mult):
                return l * r
            else:
                return f"{self._parse_arg(x.left)}{x.op.__str__()}{self._parse_arg(x.right)}"
        elif type(x) == ast.Str:
            return x.s
        elif type(x) == ast.Call:
            return f"[[[{self._parse_arg(x.func)}({', '.join([self._parse_arg(y) for y in x.args])})]]]"
        else:
            return f"{type(x)}"

    def visit_Call(self, node):
        if isinstance(node.func, ast.Attribute):
            name = None
            try:
                name = node.func.attr
            except:
                pass
            if node.func.attr == 'say':
                sentence = self._parse_arg(node.args[0])
                if not sentence in self.sentences_set:
                    self.sentences.append(sentence)
                self.sentences_set.add(sentence)
            if node.func.attr == 'set_title':
                arg = self._parse_arg(node.args[0])
                self.title = arg

with open(sys.argv[1], "r") as source:
    tree = ast.parse(source.read())

analyzer = Analyzer()
analyzer.visit(tree)
result = {}
result['title'] = analyzer.title
result['sentences'] = analyzer.sentences
print(json.dumps(result))