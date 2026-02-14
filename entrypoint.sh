#!/bin/sh

# --- 1. SSL Certificate Generation ---
if [ ! -f /etc/ssl/private/pure-ftpd.pem ]; then
    echo "Generating self-signed SSL certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/pure-ftpd.pem \
        -out /etc/ssl/private/pure-ftpd.pem \
        -subj "/C=US/ST=Denial/L=Springfield/O=Dis/CN=ftpserver"
    chmod 600 /etc/ssl/private/pure-ftpd.pem
fi

# --- 2. User Creation ---
addgroup -g 1000 ftpgroup
adduser -D -G ftpgroup -h /home/ftpusers -u 1000 ftpuser

create_user() {
    local USER=$1
    local PASS=$2
    if [ -n "$USER" ] && [ -n "$PASS" ]; then
        echo "Creating user: $USER"
        mkdir -p /home/ftpusers/$USER
        chown -R ftpuser:ftpgroup /home/ftpusers/$USER
        (echo "$PASS"; echo "$PASS") | pure-pw useradd $USER -u ftpuser -d /home/ftpusers/$USER -f /etc/pure-ftpd/passwd
    fi
}

create_user "$FTP_USER1" "$FTP_PASS1"
create_user "$FTP_USER2" "$FTP_PASS2"

pure-pw mkdb /etc/pure-ftpd/pureftpd.pdb -f /etc/pure-ftpd/passwd

# --- 3. Start Pure-FTPd ---
echo "Starting Pure-FTPd with External IP: $EXTERNAL_IP"

# -p 30000:30500 : Sets the new, larger passive port range
exec /usr/sbin/pure-ftpd \
    -l puredb:/etc/pure-ftpd/pureftpd.pdb \
    -E \
    -j \
    -R \
    -P "$EXTERNAL_IP" \
    -p 30000:30500 \
    -C 129 \
    -Y 2