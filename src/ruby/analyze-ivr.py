import ast
import sys
import re

class NonConstSentenceError(Exception):
    pass

def split_sentences(s):
    s = re.sub(r"\s+", ' ', s)
    s = s.strip()
    results = []
    i = 0
    buf = ''
    for part in re.split(r'([^\d][\.\?!]+)', s):
        if i == 0:
            buf = part
            i = 1
        elif i == 1:
            results.append((buf + part).strip())
            i = 0

    return results

class Analyzer(ast.NodeVisitor):
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
        else:
            return type(x)

    def visit_Call(self, node):
        # print(type(node))
        if isinstance(node.func, ast.Attribute):
            name = None
            try:
                name = node.func.attr
            except:
                pass
            if node.func.attr == 'say':
                try:
                    arg = self._parse_arg(node.args[0])
                    for sentence in split_sentences(arg):
                        print(f"[{sentence}]")
                except NonConstSentenceError:
                    print(f"Error in line {node.lineno}")
                    # raise
                    pass
        # self.generic_visit(node)
        # sys.exit(1)

with open(sys.argv[1], "r") as source:
    tree = ast.parse(source.read())

analyzer = Analyzer()
analyzer.visit(tree)
