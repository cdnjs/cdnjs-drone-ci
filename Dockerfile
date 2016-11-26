FROM alpine:3.3
MAINTAINER Peter Dave Hello <hsu@peterdavehello.org>
RUN apk -Uuv add openssh-client rsync git nodejs sshpass
ADD cdnjs.sh /bin/
ENTRYPOINT /bin/cdnjs.sh
