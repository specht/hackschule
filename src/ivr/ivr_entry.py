class Game(AnswerPhone):
    def run(self):
        self.bg_play('https://youtu.be/-xRD8VmjBQM')
        self.sleep(3000)
        self.say("Hallo und herzlich willkommen in der Hackschule.")
        self.sleep(2000)
        self.say("Leider können wir deinen Anruf momentan nicht persönlich entgegennehmen.")
        self.sleep(2000)
        while True:
            self.say("Bitte gib deinen vierstelligen Code ein, um ein Spiel zu starten.")
            self.sleep(2000)
            self.say("Falls du keinen Code hast, kannst du auch ein zufälliges Spiel starten. Drücke dafür bitte einfach die 0.")
            self.sleep(20000)
            code = self.dtmf(4)
            self._dispatch(code)
        self.hangup()
