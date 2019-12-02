FROM node:8-alpine

RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
      bash \
      git \
      openssh

RUN npm i -g fx ymlx

RUN mkdir /scripts
COPY match /scripts/match
RUN chmod +x /scripts/match
RUN ln -s /scripts/match /usr/local/bin/match

RUN mkdir /gitrepo
VOLUME [ "/gitrepo" ]
WORKDIR /gitrepo

COPY ./release* /scripts/

RUN chmod +x /scripts/*

RUN mkdir -p /root/.ssh
RUN ssh-keyscan -t rsa github.com gitlab.com >> /root/.ssh/known_hosts

COPY .docker.entrypoint.sh /
RUN chmod +x /.docker.entrypoint.sh

ENTRYPOINT [ "/.docker.entrypoint.sh" ]
CMD [ "--help" ]
