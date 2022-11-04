import glob
import random

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
            self.say("Momentan sind keine Spiele verfügbar.")
            self.sleep(2000)
            self.say("Wenn du das ändern möchtest, schreib dein eigenes Spiel unter w, w, w. hackschule. d, e.")
            self.sleep(20000)
            return
        while True:
            available_codes = [os.path.basename(x) for x in glob.glob('/ivr/live/*')]
            self.say("Bitte gib deinen vierstelligen Code ein, um ein Spiel zu starten.")
            if len(available_codes) > 0:
                self.sleep(2000)
                self.say("Falls du keinen Code hast, kannst du auch ein zufälliges Spiel starten. Drücke dafür bitte einfach die 0.")
            self.sleep(20000)
            code = self.dtmf(4)
            if len(available_codes) > 0 and code == '0':
                code = random.choice(available_codes)
            if code in available_codes:
                self._dispatch(code)
            else:
                self.say(f"Tut mir leid, aber ein Spiel mit dem Code {', '.join(list(code))} gibt es momentan nicht.")
