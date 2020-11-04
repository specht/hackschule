# Hackschule

Voraussetzungen: `docker`, `docker-compose`, `ruby`.

## Development Umgebung

Zum lokal ausprobieren einfach folgende Variable in `~/.bashrc` setzen:

    export QTS_DEVELOPMENT=1
    
Dann die `credentials.template.rb` unter `credentials.rb` speichern und eigene Werte einsetzen. Außerdem muss die `src/ruby/invitations.template.txt` als `src/ruby/invitations.txt` gespeichert werden und es sollte auch eine E-Mail-Adresse drinstehen.

Start mit:

    ./config.rb build
    ./config.rb up
    
`config.rb` schreibt die Datei `docker-compose.yaml` und ruft anschließend `docker-compose` mit den übergebenen Argumenten auf. Die Seite läuft dann unter `http://localhost:8020`, Neo4j unter `http://localhost:8021`.

In einer Development Umgebung werden zum einloggen keine E-Mails verschickt.
Stattdessen werden die E-Mails auf der Kommandozeile ausgegeben, so kann der normale Login Prozess getestet werden.
Alternativ können auch die folgenden Credentials genutzt werden:

Nutzername: `fs@hackschule.de`
Code: `123456`
