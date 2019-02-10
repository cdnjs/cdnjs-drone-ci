FROM node:10-alpine
LABEL maintainer="Peter Dave Hello <hsu@peterdavehello.org>"
LABEL name="cdnjs-drone-ci"
LABEL version="latest"
ENV NPM_CONFIG_LOGLEVEL error
RUN echo '@edge http://dl-cdn.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories && \
    apk -U upgrade && \
    apk -v add openssh-client rsync git@edge sshpass coreutils gawk openssl curl ca-certificates jq && \
    rm -rf /var/cache/apk/*
RUN npm install --global jsonlint && \
    rm -rf "$HOME/.npm"
RUN ssh -V && \
    git --version && \
    node --version && \
    curl --version && \
    rsync --version && \
    jq --version && \
    jsonlint -h
RUN date > /build-date
COPY cdnjs.sh /bin/
COPY ColorEchoForShell/dist/ColorEcho.sh /
ENTRYPOINT ["/bin/cdnjs.sh"]
