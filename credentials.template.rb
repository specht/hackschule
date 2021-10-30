# ----------------------------------------------------------
# Notwendige Angaben
# ----------------------------------------------------------

ADMIN_MAIL_ADDRESSES = ['HIER_EMAIL_EINFÜGEN']

# deine lokale UID, steckt auch in docker/*/Dockerfile drin und sollte 
# ggfs. dort angepasst werden
UID = 1000 

RATE_LIMIT = 0 # bytes per second, set to 0 to turn off
SCRIPT_TIMEOUT = 60 # Timeout für alle Skripte in Sekunden

SMTP_SERVER = 'smtps.udag.de'
IMAP_SERVER = 'imaps.udag.de'
SMTP_USER = 'HIER_USER_EINFÜGEN'
SMTP_PASSWORD = 'HIER_PASSWORT_EINFÜGEN'
SMTP_DOMAIN = 'HIER_DOMAIN_EINFÜGEN'
SMTP_FROM = 'HIER_ABSENDERADRESSE_EINFÜGEN'

if defined? Mail
    Mail.defaults do
    delivery_method :smtp, { 
        :address => SMTP_SERVER,
        :port => 587,
        :domain => SMTP_DOMAIN,
        :user_name => SMTP_USER,
        :password => SMTP_PASSWORD,
        :authentication => 'login',
        :enable_starttls_auto => true  
    }
    end
end

# ----------------------------------------------------------
# Für das Live-System mit Letsencrypt-Frontend
# ----------------------------------------------------------

# Domain, auf der die Live-Seite läuft
WEBSITE_HOST = 'HIER_LIVE_HOST_EINFÜGEN' # z. B. hackschule.de
# E-Mail für Letsencrypt
LETSENCRYPT_EMAIL = 'HIER_EMAIL_EINFÜGEN'

WEB_ROOT = ENV['DEVELOPMENT'] ? 'http://localhost:8025' : "https://#{WEBSITE_HOST}"
PYSANDBOX = ENV['DEVELOPMENT'] ? 'codedev_pysandbox_1' : 'code_pysandbox_1'

MYSQL_ROOT_PASSWORD = 'PLEASE_CHOOSE_A_LONG_RANDOM_PASSWORD'
MYSQL_PASSWORD_SALT = 'PLEASE_CHOOSE_A_LONG_RANDOM_SALT'

PHPMYADMIN_HOST = ENV['DEVELOPMENT'] ? 'http://localhost:8026' : "https://#{WEBSITE_HOST}"
