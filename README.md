# Hackschule

Voraussetzungen: `docker`, `docker-compose`, `ruby`.

Zum lokal ausprobieren einfach folgende Variable in `~/.bashrc` setzen:

    export QTS_DEVELOPMENT=1
    
Dann die `credentials.template.rb` unter `credentials.rb` speichern und eigene Werte einsetzen. Außerdem muss die `src/ruby/invitations.template.txt` als ``src/ruby/invitations.txt` gespeichert werden und es sollte auch eine E-Mail-Adresse drinstehen.

Start mit:

    ./config.rb build
    ./config.rb up
    
`config.rb` schreibt die Datei `docker-compose.yaml` und ruft anschließend `docker-compose` mit den übergebenen Argumenten auf. Die Seite läuft dann unter `http://localhost:8020`, Neo4j unter `http://localhost:8021`.
