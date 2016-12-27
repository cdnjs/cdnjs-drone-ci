FROM node:4-alpine
MAINTAINER Peter Dave Hello <hsu@peterdavehello.org>
ENV NPM_CONFIG_LOGLEVEL warn
RUN echo '@edge http://dl-cdn.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories
RUN apk -U upgrade && \
    apk -v add openssh-client rsync git@edge sshpass coreutils gawk && \
    rm -rf /var/cache/apk/*
RUN ssh -V
RUN git --version
RUN node --version
RUN rsync --version
ADD cdnjs.sh /bin/
ADD ColorEchoForShell/dist/ColorEcho.sh /
ENTRYPOINT /bin/cdnjs.sh
