FROM alpine:latest

# [cite_start]Install pure-ftpd and openssl [cite: 1]
RUN apk --no-cache add pure-ftpd openssl

# Create necessary directories
# We add /config for persistent storage
RUN mkdir -p /etc/ssl/private /etc/pure-ftpd /home/ftpusers /config

# Copy the entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV LANG=C.UTF-8

# Expose FTP Control port and Passive Data ports
EXPOSE 21 30000-30500

# Declare the mount point for external config
VOLUME ["/config"]

ENTRYPOINT ["/entrypoint.sh"]