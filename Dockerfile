FROM phusion/baseimage:jammy-1.0.4

LABEL app.backupbrain.image.authors="masukomi@masukomi.org"


# allow apt to work with https-based sources
RUN apt-get update -yqq && \
    apt-get upgrade -yqq && \
    apt-get install -yqq --no-install-recommends \
      apt-utils \
      apt-transport-https

# Make sure we've got the base stuff we need
RUN apt-get update -yqq && \
    apt-get install -yqq --no-install-recommends \
      gnupg\
      curl\
      git

WORKDIR /app
