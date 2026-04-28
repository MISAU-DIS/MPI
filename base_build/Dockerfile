# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.2.0
FROM ruby:${RUBY_VERSION}-alpine

RUN apk update --no-cache && \
    apk add --no-cache \
    build-base \
    mysql-dev \
    nodejs \
    npm \
    tzdata \
    git \
    bash \
    curl \
    xz \
    shared-mime-info \
    iputils \
    busybox-extras \
    libstdc++ \
    redis

WORKDIR /app
