#!/bin/sh

# Ensure the config directories exist immediately
mkdir -p /etc/pure-ftpd/ssl
mkdir -p /home/ftpusers

# --- 1. SSL Persistence ---
CERT_FILE="/etc/pure-ftpd/ssl/pure-ftpd.pem"

if [ ! -f "$CERT_FILE" ]; then
    echo "No cached SSL found. Generating permanent certificate..."
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$CERT_FILE" \
        -out "$CERT_FILE" \
        -subj "/C=US/ST=DE/L=Berlin/O=FTP/CN=ftpserver"
    chmod 600 "$CERT_FILE"
else
    echo "Using cached SSL certificate: $CERT_FILE"
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
        echo "Configuring user: $USER"
        mkdir -p "$HOME"
        chown -R 82:82 "$HOME"
        # Delete existing entry in the passwd file to prevent duplicates
        pure-pw userdel "$USER" -f /etc/pure-ftpd/passwd 2>/dev/null
        # Add the user back with fresh settings
        (echo "$PASS"; echo "$PASS") | pure-pw useradd "$USER" -f /etc/pure-ftpd/passwd -u 82 -g 82 -d "$HOME"
    fi
}

# User 1: Primary
create_virtual_user "$FTP_USER1" "$FTP_PASS1" "/home/ftpusers/$FTP_USER1"

# User 2: Nested
if [ -z "$FTP_USER2_DIR" ]; then
    echo "CRITICAL ERROR: FTP_USER2_DIR is missing. Loop prevented by exit 1."
    exit 1
fi
create_virtual_user "$FTP_USER2" "$FTP_PASS2" "/home/ftpusers/$FTP_USER1/$FTP_USER2_DIR"

# Generate the binary database file
pure-pw mkdb /etc/pure-ftpd/pureftpd.pdb -f /etc/pure-ftpd/passwd

# --- 4. Start ---
echo "Starting Pure-FTPd on $EXTERNAL_IP..."
# We use the -Y 2 flag and -J to specify the exact cert file path
exec /usr/sbin/pure-ftpd \
    -l puredb:/etc/pure-ftpd/pureftpd.pdb \
    -E -j -R \
    -P "$EXTERNAL_IP" \
    -p 30000:30500 \
    -C 129 \
    -Y 2 \
    -J "$CERT_FILE"