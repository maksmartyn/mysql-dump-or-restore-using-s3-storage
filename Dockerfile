FROM alpine:3.20

RUN apk update \
    && apk add --no-cache \
    python3 \
    py3-magic \
    s3cmd \
    gzip \
    ca-certificates \
    mysql-client \
    mariadb-connector-c 

RUN mkdir "/app"

WORKDIR /app

ADD main.py /app/main.py

ENTRYPOINT [ "/usr/bin/python3", "/app/main.py" ]