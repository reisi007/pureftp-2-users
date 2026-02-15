#!/bin/sh

# --- 1. SSL Certificate Setup ---
# We keep the name pure-ftpd.pem to maintain compatibility with existing 
# persistence volumes if you switch back and forth.
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
# Link the cert to where ProFTPD expects it
ln -sf "$CERT_FILE" "$TARGET_FILE"

# --- 2. Configuration Injection ---
# Inject the EXTERNAL_IP into the ProFTPD config
if [ -n "$EXTERNAL_IP" ]; then
    sed -i "s/__EXTERNAL_IP__/$EXTERNAL_IP/g" /etc/proftpd/proftpd.conf
else
    # Fallback if no IP provided (though your compose has one)
    sed -i "s/MasqueradeAddress.*//g" /etc/proftpd/proftpd.conf
fi

# --- 3. System Setup ---
# Create the group. We use GID 82 (standard www-data/ftp often used in Alpine)
getent group 82 >/dev/null || addgroup -g 82 ftpgroup
FTP_GROUP_NAME=$(getent group 82 | cut -d: -f1)

# Start UIDs at 1000 to match typical host user permissions
CURRENT_UID=1000
AUTH_FILE="/etc/proftpd/ftpd.passwd"

# Create the auth file
touch "$AUTH_FILE"
chmod 440 "$AUTH_FILE"
chown root:82 "$AUTH_FILE"

create_virtual_user() {
    local USER=$1
    local PASS=$2
    local HOME=$3
    
    # Check for UID conflicts
    while getent passwd "$CURRENT_UID" >/dev/null; do
        CURRENT_UID=$((CURRENT_UID + 1))
    done

    echo "Creating user '$USER' (UID $CURRENT_UID) -> $HOME"
    
    # 1. Create system user (for file ownership/permissions)
    adduser -D -G "$FTP_GROUP_NAME" -h "$HOME" -u "$CURRENT_UID" -s /bin/false "ftp_$USER"
    
    # 2. Ensure Home exists and has permissions
    mkdir -p "$HOME"
    chown -R "$CURRENT_UID:82" "$HOME"
    
    # 3. Add to ProFTPD virtual user database
    # --stdin reads password from standard input
    echo "$PASS" | ftpasswd --passwd --name "$USER" \
        --file "$AUTH_FILE" \
        --uid "$CURRENT_UID" --gid 82 \
        --home "$HOME" --shell /bin/false \
        --stdin
        
    CURRENT_UID=$((CURRENT_UID + 1))
}

# --- 4. Dynamic User Creation Loop ---
i=1
while true; do
    user_var="FTP_USER_$i"
    pass_var="FTP_PASS_$i"
    home_var="FTP_HOME_$i"

    eval USER_VAL=\$$user_var
    eval PASS_VAL=\$$pass_var
    eval HOME_VAL=\$$home_var

    if [ -z "$USER_VAL" ]; then
        if [ "$i" -eq 1 ]; then
            echo "WARNING: No FTP_USER_1 defined. No users created."
        fi
        break
    fi

    if [ -z "$HOME_VAL" ]; then
        HOME_VAL="/home/ftpusers/$USER_VAL"
    fi

    if [ -n "$PASS_VAL" ]; then
        create_virtual_user "$USER_VAL" "$PASS_VAL" "$HOME_VAL"
    else
        echo "Skipping $USER_VAL: Password not set."
    fi

    i=$((i + 1))
done

# --- 5. Start ProFTPD ---
echo "Starting ProFTPD..."
# -n: No daemon (foreground)
# -c: Config file
exec proftpd -n -c /etc/proftpd/proftpd.conf