FROM node:4-alpine
MAINTAINER Peter Dave Hello <hsu@peterdavehello.org>
RUN apk -Uuv add openssh-client rsync git sshpass
ADD cdnjs.sh /bin/
ENTRYPOINT /bin/cdnjs.sh
