#!/bin/sh

# --- 1. SSL Zertifikat ---
if [ ! -f /etc/ssl/private/pure-ftpd.pem ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/pure-ftpd.pem \
        -out /etc/ssl/private/pure-ftpd.pem \
        -subj "/C=US/ST=DE/L=Berlin/O=FTP/CN=ftpserver"
    chmod 600 /etc/ssl/private/pure-ftpd.pem
fi

# --- 2. System-User Setup ---
addgroup -g 1000 ftpgroup
adduser -D -G ftpgroup -h /home/ftpusers -u 1000 ftpuser

# --- 3. Benutzer-Erstellung ---
# Sicherstellen, dass die Passwort-Quelldatei leer/neu ist
truncate -s 0 /etc/pure-ftpd/passwd

create_virtual_user() {
    local USER=$1
    local PASS=$2
    local HOME=$3
    if [ -n "$USER" ] && [ -n "$PASS" ]; then
        mkdir -p "$HOME"
        chown -R ftpuser:ftpgroup "$HOME"
        # Benutzer zur Text-Datenbank hinzufügen
        (echo "$PASS"; echo "$PASS") | pure-pw useradd "$USER" -f /etc/pure-ftpd/passwd -u ftpuser -d "$HOME"
    fi
}

# User 1
USER1_HOME="/home/ftpusers/$FTP_USER1"
create_virtual_user "$FTP_USER1" "$FTP_PASS1" "$USER1_HOME"

# User 2 Validierung & Erstellung
if [ -z "$FTP_USER2_DIR" ]; then
    echo "ERROR: FTP_USER2_DIR is not set."
    exit 1
fi
USER2_HOME="$USER1_HOME/$FTP_USER2_DIR"
create_virtual_user "$FTP_USER2" "$FTP_PASS2" "$USER2_HOME"

# --- 4. Datenbank-Index erstellen (Löst deinen Fehler) ---
pure-pw mkdb /etc/pure-ftpd/pureftpd.pdb -f /etc/pure-ftpd/passwd

# --- 5. Start ---
echo "Pure-FTPd wird gestartet..."
# Wir nutzen -lpuredb:<PFAD-ZUR-PDB> um sicherzugehen, dass er die neue Datei nutzt
exec /usr/sbin/pure-ftpd \
    -l puredb:/etc/pure-ftpd/pureftpd.pdb \
    -E -j -R \
    -P "$EXTERNAL_IP" \
    -p 30000:30500 \
    -C 129 \
    -Y 2
