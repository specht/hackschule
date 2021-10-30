# Anleitung: Hackschule lokal starten (unter Windows)

_Anmerkung vorweg: unter Linux ist das alles etwas einfacher, hier tut es z. B. ein einfaches_

```
$ sudo apt install ruby git-core docker docker-compose
```

## Installation unter Windows

_Hinweise: Bitte verwendet einen Laptop - ein Tablet reicht hier nicht. Bitte nehmt euch eine halbe Stunde und führt die Schritte schon zu Hause durch, da unsere Bandbreite im Seminar nicht so groß ist._

Achtung, es wird einiges an Speicherplatz (ca. 7 GB) benötigt:

- Ruby 80 MB
- Git 261 MB
- WSL 2 68 MB
- Docker Desktop 2,6 GB
- zusätzlich:: 4,2 GB für die Docker-Images
  - Docker und die Images belegen am meisten Speicherplatz, sie verschwinden aber wieder, wenn man Docker deinstalliert

Wir benötigen: Ruby, Git, Docker

### Ruby

- aktuelles Ruby ohne DevKit, hier ist der Link:
https://github.com/oneclick/rubyinstaller2/releases/download/RubyInstaller-3.0.2-1/rubyinstaller-3.0.2-1-x64.exe
- einfach mit Default-Optionen installieren, aber Achtung: am Ende wird nach MSYS2 gefragt, das brauchen wir nicht

### Git

- Setup herunterladen, hier ist der Link:
https://github.com/git-for-windows/git/releases/download/v2.33.1.windows.1/Git-2.33.1-64-bit.exe
- bei Editor möchtet ihr vielleicht einen anderen Editor als vim auswählen (ist aber auch egal, brauchen wir für das Seminar eh nicht)
- ansonsten einfach alle Default-Optionen so lassen

### Docker Desktop: 

- Setup hier herunterladen:
https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe
- alle Optionen so lassen (wir benötigen insbesondere WSL 2, das Linux-Subsystem für Windows)
- nach der Installation muss noch WSL 2 installiert werden:
  https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi
- einmal neustarten
- das Gerät muss Virtualisierung unterstützen (muss ggfs. im BIOS oder in Windows erst aktiviert werden, ging bei mir aber direkt so)
- Hilfe gibt's hier: https://docs.docker.com/desktop/windows/install/

Docker Desktop starten
Eingabeaufforderung starten (Win+R cmd [Enter])

## Start der Hackschule

- Hackschule herunterladen:

```
git clone https://github.com/specht/hackschule.git
cd hackschule
copy credentials.template.rb credentials.rb
```

- konfigurieren und Docker-Images bauen:

```
ruby config.rb build
```

- und starten:
```
ruby config.rb up
```

Der Start kann beim ersten mal eine Weile dauern, es ist soweit, wenn codedev-ruby-1 schreibt: "Server up and running!"

(bis hier werden einige MB heruntergeladen, also alles schon zu Hause erledigen)

Beenden der Hackschule in der Eingabeaufforderung mit Strg+C (dauert kurz).

Man kann nun folgende Seiten aufrufen:

- Hackschule: [http://localhost:8025](http://localhost:8025)
- Neo4j: [http://localhost:8021](http://localhost:8021)
- phpmyadmin: [http://localhost:8026](http://localhost:8026)
