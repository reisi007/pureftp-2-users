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

# --- 2. Base User/Group Setup ---
addgroup -g 1000 ftpgroup
adduser -D -G ftpgroup -h /home/ftpusers -u 1000 ftpuser

# Helper function to create a Pure-FTPd user
create_virtual_user() {
    local USER=$1
    local PASS=$2
    local HOME=$3

    if [ -n "$USER" ] && [ -n "$PASS" ]; then
        echo "Creating virtual user: $USER at $HOME"
        mkdir -p "$HOME"
        chown -R ftpuser:ftpgroup "$HOME"
        (echo "$PASS"; echo "$PASS") | pure-pw useradd $USER -u ftpuser -d "$HOME" -f /etc/pure-ftpd/passwd
    fi
}

# --- 3. Strict Logic for Nested Directories ---

# User 1: Primary Home
USER1_HOME="/home/ftpusers/$FTP_USER1"

# User 2: Validation (No Fallback)
if [ -z "$FTP_USER2_DIR" ]; then
    echo "ERROR: FTP_USER2_DIR is not set. Setup failed."
    exit 1
fi

USER2_HOME="$USER1_HOME/$FTP_USER2_DIR"

# --- 4. Execute Creation ---
create_virtual_user "$FTP_USER1" "$FTP_PASS1" "$USER1_HOME"
create_virtual_user "$FTP_USER2" "$FTP_PASS2" "$USER2_HOME"

# Commit changes
pure-pw mkdb /etc/pure-ftpd/pureftpd.pdb -f /etc/pure-ftpd/passwd

# --- 5. Start Pure-FTPd ---
echo "Starting Pure-FTPd..."
exec /usr/sbin/pure-ftpd \
    -l puredb:/etc/pure-ftpd/pureftpd.pdb \
    -E -j -R -P "$EXTERNAL_IP" \
    -p 30000:30500 -C 129 -Y 2