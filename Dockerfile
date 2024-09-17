FROM alpine:3.20

RUN apk update \
    && apk add --no-cache \
    python3 \
    py3-magic \
    s3cmd \
    gzip \
    ca-certificates \
    mysql-client \
    mariadb-connector-c \
    bash

SHELL [ "/bin/bash", "-c" ]

RUN mkdir "/app"

WORKDIR /app

ADD main.sh /app/main.sh

RUN chmod 777 /app/main.sh

ENTRYPOINT [ "/app/main.sh" ]