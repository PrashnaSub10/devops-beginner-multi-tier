FROM alpine:3.20

RUN apk add --no-cache bash openssl git curl

WORKDIR /backup

COPY backup.sh /backup/backup.sh
RUN chmod +x /backup/backup.sh

CMD ["/bin/bash", "/backup/backup.sh"]
