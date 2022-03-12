FROM golang:alpine AS build

RUN apk add --update imagemagick protobuf-c git bash openssl \
    && git clone https://github.com/cozy/cozy-stack.git /opt/cozy-stack \
    && cd /opt/cozy-stack \
    && scripts/build.sh release /usr/bin/cozy-stack

FROM node:16-alpine

COPY --from=build /usr/bin/cozy-stack /usr/bin/cozy-stack
COPY --from=build /opt/cozy-stack/scripts/konnector-node16-run.sh /usr/share/cozy/konnector-node16-run.sh
COPY ./cozy.template.yaml /etc/cozy/cozy.template.yaml

VOLUME [ "/var/lib/cozy", "/etc/cozy" ]

ENV COUCHDB_PORT 5984
ENV COUCHDB_PROTO http

ENV GOSU_VERSION 1.14
RUN set -eux; \
    \
    apk add --no-cache --virtual .gosu-deps \
    ca-certificates \
    dpkg \
    gnupg \
    ; \
    \
    dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
    wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
    wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
    \
    # verify the signature
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
    gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
    command -v gpgconf && gpgconf --kill all || :; \
    rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
    \
    # clean up fetch dependencies
    apk del --no-network .gosu-deps; \
    \
    chmod +x /usr/local/bin/gosu; \
    # verify that the binary works
    gosu --version; \
    gosu nobody true

RUN apk add --update yq tini bash \
    && addgroup -S cozy \
    && adduser -S -h /var/lib/cozy \
    -H -s /usr/sbin/nologin \
    -G cozy cozy-stack \
    && install -o root -g cozy -m 0750 -d /var/log/cozy \
    && install -o cozy-stack -g cozy -m 750 -d /usr/share/cozy \
    && install -o cozy-stack -g cozy -m 750 -d /var/lib/cozy \
    && chmod 755 /usr/bin/cozy-stack \
    && chown cozy-stack:cozy /usr/share/cozy/konnector-node16-run.sh \
    && chmod 750 /usr/share/cozy/konnector-node16-run.sh \
    && chown cozy-stack:cozy /var/lib/cozy \
    && chmod 750 /var/lib/cozy

COPY docker-entrypoint.sh /usr/local/bin
RUN ln -s usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh", "/usr/bin/cozy-stack", "-c", "/etc/cozy/cozy.yaml"]

# 8080: main cozy endpoint
# 6060: admin endpoint
EXPOSE 8080 6060
CMD ["serve"]
