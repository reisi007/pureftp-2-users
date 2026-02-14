FROM alpine:latest

# Install pure-ftpd and openssl
RUN apk --no-cache add pure-ftpd openssl

# Create necessary directories
RUN mkdir -p /etc/ssl/private /etc/pure-ftpd /home/ftpusers

# Copy the entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose FTP Control port and Passive Data ports
EXPOSE 21 30000-30500

ENTRYPOINT ["/entrypoint.sh"]