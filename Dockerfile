FROM node:4-alpine
MAINTAINER Peter Dave Hello <hsu@peterdavehello.org>
ENV NPM_CONFIG_LOGLEVEL warn
RUN apk -Uuv add openssh-client rsync git sshpass coreutils gawk
RUN ssh -V
RUN git --version
RUN node --version
RUN rsync --version
ADD cdnjs.sh /bin/
ENTRYPOINT /bin/cdnjs.sh
