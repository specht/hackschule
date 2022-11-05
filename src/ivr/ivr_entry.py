import glob
import random
import json

class Game(AnswerPhone):
    def run(self):
        self.bg_play('https://youtu.be/-xRD8VmjBQM')
        self.sleep(3000)
        self.say("Hallo und herzlich willkommen in der Hackschule.")
        self.sleep(2000)
        self.say("Leider können wir deinen Anruf momentan nicht persönlich entgegennehmen.")
        self.sleep(2000)
        available_codes = [os.path.basename(x) for x in glob.glob('/ivr/live/*')]
        if len(available_codes) == 0:
            self.say("Normalerweise solltest du hier Spiele spielen können. Momentan sind aber leider keine Spiele verfügbar.")
            self.sleep(2000)
            self.say("Wenn du das ändern möchtest, schreib dein eigenes Spiel unter www hackschule punkt de eh und veröffentliche es dann.")
            self.sleep(20000)
            return
        while True:
            available_codes = [os.path.basename(x) for x in glob.glob('/ivr/live/*')]
            self.say("Bitte gib deinen Code ein, um ein Spiel zu starten.")
            if len(available_codes) > 0:
                self.sleep(2000)
                self.say("Falls du keinen Code hast, kannst du auch ein zufälliges Spiel starten. Drücke dafür bitte einfach die 0.")
            present_games = sorted([int(os.path.basename(x)) for x in glob.glob('/ivr/live/*')])
            self.say("Du kannst zwischen den folgenden Spielen wählen:")
            for code in present_games:
                codes = f'{code}'
                with open(f'/ivr/live/{codes}') as f:
                    title = (json.loads(f.read()))['title']
                    self.say("Drücke die")
                    self.say(codes)
                    self.say('für:')
                    self.say(title)

            code = self.dtmf(len(str(present_games[-1])))
            if len(available_codes) > 0 and code == '0':
                code = random.choice(available_codes)
            if code in available_codes:
                self._dispatch(code)
            else:
                self.say("Tut mir leid, aber ein Spiel mit dem Code")
                self.say(', '.join(list(code)))
                self.say("gibt es momentan nicht.")
