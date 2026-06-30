# syntax=docker/dockerfile:1

FROM alpine:3.22

RUN apk add --no-cache \
        bash \
        coreutils

COPY scripts/guardian.sh /usr/local/bin/productivity-guardian
COPY docker/healthcheck.sh /usr/local/bin/guardian-healthcheck
COPY configs/guardian.conf.example /etc/productivity-guardian/guardian.conf

RUN chmod 0755 \
        /usr/local/bin/productivity-guardian \
        /usr/local/bin/guardian-healthcheck

ENV GUARDIAN_CONFIG=/etc/productivity-guardian/guardian.conf \
    GUARDIAN_HEARTBEAT_FILE=/tmp/productivity-guardian.heartbeat \
    GUARDIAN_HOME=/host-home \
    GUARDIAN_LOG_TARGET=stdout \
    GUARDIAN_NOTIFICATIONS=false

ENTRYPOINT ["/usr/local/bin/productivity-guardian"]
CMD ["files"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/usr/local/bin/guardian-healthcheck"]
