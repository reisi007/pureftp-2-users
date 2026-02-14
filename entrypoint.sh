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

# --- 2. System Group Setup ---
# Ensure GID 82 exists (usually www-data)
getent group 82 >/dev/null || addgroup -g 82 ftpgroup
FTP_GROUP_NAME=$(getent group 82 | cut -d: -f1)

# Initialize UID counter
CURRENT_UID=1000

# --- 3. Pure-FTPd Database Setup ---
mkdir -p /etc/pure-ftpd
touch /etc/pure-ftpd/passwd

create_virtual_user() {
    local USER=$1
    local PASS=$2
    local HOME=$3
    
    if [ -n "$USER" ] && [ -n "$PASS" ]; then
        # Check if the UID is already taken by an existing system user
        while getent passwd "$CURRENT_UID" >/dev/null; do
            CURRENT_UID=$((CURRENT_UID + 1))
        done

        echo "Creating virtual user '$USER' mapped to system UID $CURRENT_UID..."
        
        # 1. Create a system-level user for this specific FTP user
        # We use 'ftp_$USER' to avoid naming conflicts
        adduser -D -G "$FTP_GROUP_NAME" -h "$HOME" -u "$CURRENT_UID" "ftp_$USER"
        
        # 2. Set directory permissions
        mkdir -p "$HOME"
        chown -R "$CURRENT_UID:82" "$HOME"
        
        # 3. Add to Pure-FTPd database
        # -u specifies the specific UID, -g specifies the shared GID 82
        (echo "$PASS"; echo "$PASS") | pure-pw useradd "$USER" \
            -f /etc/pure-ftpd/passwd \
            -u "$CURRENT_UID" \
            -g 82 \
            -d "$HOME"
            
        # Increment for the next call
        CURRENT_UID=$((CURRENT_UID + 1))
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
    -E -j \
    -P "$EXTERNAL_IP" \
    -p 30000:30500 \
    -C 129 \
    -Y 2