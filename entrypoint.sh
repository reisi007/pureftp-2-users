#!/bin/sh

# --- 1. SSL Certificate Setup ---
CERT_DIR="/config"
CERT_FILE="$CERT_DIR/pure-ftpd.pem"
TARGET_FILE="/etc/ssl/private/pure-ftpd.pem"

mkdir -p "$CERT_DIR"
if [ ! -f "$CERT_FILE" ]; then
    echo "Generating SSL certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$CERT_FILE" -out "$CERT_FILE" \
        -subj "/C=US/ST=DE/L=Berlin/O=FTP/CN=ftpserver"
    chmod 600 "$CERT_FILE"
fi
ln -sf "$CERT_FILE" "$TARGET_FILE"

# --- 2. System Setup ---
getent group 82 >/dev/null || addgroup -g 82 ftpgroup
FTP_GROUP_NAME=$(getent group 82 | cut -d: -f1)
CURRENT_UID=1000

mkdir -p /etc/pure-ftpd
touch /etc/pure-ftpd/passwd

create_virtual_user() {
    local USER=$1
    local PASS=$2
    local HOME=$3
    
    # Check for UID conflicts
    while getent passwd "$CURRENT_UID" >/dev/null; do
        CURRENT_UID=$((CURRENT_UID + 1))
    done

    echo "Creating user '$USER' (UID $CURRENT_UID) -> $HOME"
    
    adduser -D -G "$FTP_GROUP_NAME" -h "$HOME" -u "$CURRENT_UID" "ftp_$USER"
    mkdir -p "$HOME"
    chown -R "$CURRENT_UID:82" "$HOME"
    
    (echo "$PASS"; echo "$PASS") | pure-pw useradd "$USER" \
        -f /etc/pure-ftpd/passwd \
        -u "$CURRENT_UID" -g 82 \
        -d "$HOME"
        
    CURRENT_UID=$((CURRENT_UID + 1))
}

# --- 3. Dynamic User Creation Loop ---
# We loop through index i=1, 2, 3... looking for FTP_USER_i
i=1
while true; do
    # Construct variable names dynamically
    # Note: We use _ (underscore) as separator: FTP_USER_1, FTP_PASS_1
    user_var="FTP_USER_$i"
    pass_var="FTP_PASS_$i"
    home_var="FTP_HOME_$i"

    # Use eval to pull the value of the variable name
    eval USER_VAL=\$$user_var
    eval PASS_VAL=\$$pass_var
    eval HOME_VAL=\$$home_var

    # Stop if the user variable is empty
    if [ -z "$USER_VAL" ]; then
        # Check if we just haven't started yet, or if we are done
        if [ "$i" -eq 1 ]; then
            echo "WARNING: No FTP_USER_1 defined. No users created."
        fi
        break
    fi

    # Default home directory if not provided
    if [ -z "$HOME_VAL" ]; then
        HOME_VAL="/home/ftpusers/$USER_VAL"
    fi

    # Create the user
    if [ -n "$PASS_VAL" ]; then
        create_virtual_user "$USER_VAL" "$PASS_VAL" "$HOME_VAL"
    else
        echo "Skipping $USER_VAL: Password not set."
    fi

    i=$((i + 1))
done

pure-pw mkdb /etc/pure-ftpd/pureftpd.pdb -f /etc/pure-ftpd/passwd

# --- 4. Start ---
echo "Starting Pure-FTPd..."
exec /usr/sbin/pure-ftpd \
    -l puredb:/etc/pure-ftpd/pureftpd.pdb \
    -E -j \
    -P "$EXTERNAL_IP" \
    -p 30000:30500 \
    -C 129 \
    -Y 2