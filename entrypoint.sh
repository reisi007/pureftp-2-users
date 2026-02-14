#!/bin/sh

# --- 1. SSL Certificate ---
if [ ! -f /etc/ssl/private/pure-ftpd.pem ]; then
    echo "Generating SSL certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/pure-ftpd.pem \
        -out /etc/ssl/private/pure-ftpd.pem \
        -subj "/C=US/ST=DE/L=Berlin/O=FTP/CN=ftpserver"
    chmod 600 /etc/ssl/private/pure-ftpd.pem
fi

# --- 2. System-User Setup ---
# Check if group/user already exists to avoid errors on restart
getent group ftpgroup >/dev/null || addgroup -g 1000 ftpgroup
getent passwd ftpuser >/dev/null || adduser -D -G ftpgroup -h /home/ftpusers -u 1000 ftpuser

# --- 3. Pure-FTPd Database Setup ---
# Ensure the config directory and file exist
mkdir -p /etc/pure-ftpd
touch /etc/pure-ftpd/passwd

create_virtual_user() {
    local USER=$1
    local PASS=$2
    local HOME=$3
    if [ -n "$USER" ] && [ -n "$PASS" ]; then
        echo "Creating virtual user: $USER"
        mkdir -p "$HOME"
        chown -R ftpuser:ftpgroup "$HOME"
        # -f specifies the file, -m commits to pdb immediately
        (echo "$PASS"; echo "$PASS") | pure-pw useradd "$USER" -f /etc/pure-ftpd/passwd -u ftpuser -d "$HOME"
    fi
}

# Create User 1
USER1_HOME="/home/ftpusers/$FTP_USER1"
create_virtual_user "$FTP_USER1" "$FTP_PASS1" "$USER1_HOME"

# Create User 2
if [ -z "$FTP_USER2_DIR" ]; then
    echo "ERROR: FTP_USER2_DIR is not set. Exiting."
    exit 1
fi
USER2_HOME="$USER1_HOME/$FTP_USER2_DIR"
create_virtual_user "$FTP_USER2" "$FTP_PASS2" "$USER2_HOME"

# Finalize the DB
pure-pw mkdb /etc/pure-ftpd/pureftpd.pdb -f /etc/pure-ftpd/passwd

# --- 4. Start ---
echo "Starting Pure-FTPd on $EXTERNAL_IP..."
exec /usr/sbin/pure-ftpd \
    -l puredb:/etc/pure-ftpd/pureftpd.pdb \
    -E -j -R \
    -P "$EXTERNAL_IP" \
    -p 30000:30500 \
    -C 129 \
    -Y 2