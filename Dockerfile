FROM alpine:latest

# Install ProFTPD, Utils (for ftpasswd), Crypto (for SSL), and OpenSSL
RUN apk --no-cache add \
    proftpd \
    proftpd-utils \
    openssl

# Create necessary directories
# /config matches the volume mount in your compose file
RUN mkdir -p /run/proftpd /etc/ssl/private /home/ftpusers /config

# Copy configuration and entrypoint
COPY proftpd.conf /etc/proftpd/proftpd.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose FTP Control port and Passive Data ports (same as before)
EXPOSE 21 30000-30500

# Declare the mount point for external config
VOLUME ["/config"]

ENTRYPOINT ["/entrypoint.sh"]