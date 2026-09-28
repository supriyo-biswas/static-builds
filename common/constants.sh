# shellcheck shell=bash

export REF_URL=https://raw.githubusercontent.com/curl/curl/curl-8_22_0/README.md

export TEST_IMAGES="
    ubuntu:latest
    ubuntu:devel
    debian:latest
    debian:oldstable
    debian:testing
    alpine:latest
    fedora:latest
    rockylinux/rockylinux:8
    rockylinux/rockylinux:9
    almalinux:8
    almalinux:9
"

export TEST_SSH_IMAGES="
    ubuntu:latest
    ubuntu:devel
    debian:latest
    debian:oldstable
    debian:testing
"
