#!/bin/sh

# --- 1. SSL Persistence ---
# We store the cert in a subfolder of our config volume
mkdir -p /etc/pure-ftpd/ssl
CERT_FILE="/etc/pure-ftpd/ssl/pure-ftpd.pem"

if [ ! -f "$CERT_FILE" ]; then
    echo "No cached SSL found. Generating permanent certificate..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CERT_FILE" \
        -out "$CERT_FILE" \
        -subj "/C=US/ST=DE/L=Berlin/O=FTP/CN=ftpserver"
    chmod 600 "$CERT_FILE"
else
    echo "Using cached SSL certificate."
fi

# --- 2. System-User Setup (GID 82) ---
getent group ftpgroup >/dev/null || addgroup -g 82 ftpgroup
getent passwd ftpuser >/dev/null || adduser -D -G ftpgroup -h /home/ftpusers -u 82 ftpuser

# --- 3. Pure-FTPd Database ---
touch /etc/pure-ftpd/passwd

create_virtual_user() {
    local USER=$1
    local PASS=$2
    local HOME=$3
    if [ -n "$USER" ] && [ -n "$PASS" ]; then
        echo "Updating virtual user: $USER"
        mkdir -p "$HOME"
        chown -R 82:82 "$HOME"
        # We use 'pure-pw userdel' first to ensure we don't have duplicates if the DB is cached
        pure-pw userdel "$USER" -f /etc/pure-ftpd/passwd 2>/dev/null
        (echo "$PASS"; echo "$PASS") | pure-pw useradd "$USER" -f /etc/pure-ftpd/passwd -u 82 -g 82 -d "$HOME"
    fi
}

create_virtual_user "$FTP_USER1" "$FTP_PASS1" "/home/ftpusers/$FTP_USER1"
create_virtual_user "$FTP_USER2" "$FTP_PASS2" "/home/ftpusers/$FTP_USER1/$FTP_USER2_DIR"

pure-pw mkdb /etc/pure-ftpd/pureftpd.pdb -f /etc/pure-ftpd/passwd

# --- 4. Start ---
# Point to the persistent cert path
exec /usr/sbin/pure-ftpd \
    -l puredb:/etc/pure-ftpd/pureftpd.pdb \
    -E -j -R -P "$EXTERNAL_IP" -p 30000:30500 -C 129 \
    -Y 2 \
    -p 30000:30500 \
    -H \
    -S 21 \
    --tls=2 \
    -u 82 \
    -g 82 \
    -K