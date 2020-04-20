import sys
import subprocess

email = sys.argv[1].strip()
if len(email) == 0:
    sys.exit(1)

result = subprocess.run(['ps', 'ax', '-o', 'pid='], stdout=subprocess.PIPE).stdout.decode('utf-8')
test = f'/sandbox/{email}/'
for line in result.split("\n"):
    line = line.strip()
    if len(line) == 0:
        continue
    pid = int(line)
    cmdline = subprocess.run(['cat', f'/proc/{pid}/cmdline'], stdout=subprocess.PIPE).stdout.decode('utf-8')
    if cmdline[0:7] == 'python3' and test in cmdline:
        subprocess.run(['kill', f'{pid}'], stdout=subprocess.PIPE).stdout.decode('utf-8')
