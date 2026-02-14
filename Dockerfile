FROM alpine:latest

# Install pure-ftpd and openssl
RUN apk --no-cache add pure-ftpd openssl

# Create directory for SSL certificates
RUN mkdir -p /etc/ssl/private

# Copy the entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose FTP Control port (21) and NEW Passive Data ports (30000-30500)
EXPOSE 21 30000-30500

ENTRYPOINT ["/entrypoint.sh"]