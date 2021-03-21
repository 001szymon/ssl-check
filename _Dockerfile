FROM alpine:3.12

RUN apk update && \
    apk upgrade && \
    apk add bash git coreutils curl wget openssl && \
    rm -fR /var/cache/apk/* && \
    addgroup sslcheck && \
    adduser -G sslcheck -g "sslcheck user"  -s /bin/bash -D sslcheck && \
    ln -s /home/sslcheck/sslcheck.sh /usr/local/bin/ && \
    mkdir -m 755 -p /home/sslcheck/etc /home/sslcheck/bin

USER sslcheck
WORKDIR /home/sslcheck/

COPY --chown=sslcheck:sslcheck etc/. /home/sslcheck/etc/
COPY --chown=sslcheck:sslcheck bin/. /home/sslcheck/bin/
COPY --chown=sslcheck:sslcheck sslcheck.sh  /home/sslcheck/

ENTRYPOINT ["sslcheck.sh"]

CMD ["-h"]
