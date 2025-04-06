# static-builds

Statically-built, dependency free binaries of software packages for Linux. Just extract the binaries, add to your system, and run them!

Perfect for servers with limited installation capabilties (e.g. recovery situations), containerized environments or CI runners where pulling in a binary dependency with multiple files may not be possible.

In Golang, it is possible to create an executable that works on the target OS and architecture without having any other dependencies, ensuring that the only thing you need to run your software is to deploy the single binary in the server or container. This project aims to create a similar experience for other software packages.

## Installation

Head over to the [releases](https://github.com/supriyo-biswas/static-builds/releases) to download the binaries.

Some binaries have some special requirements:

* `curl`/`wget`/`git`: To download HTTPS content, you need to add a certificate bundle into `/etc/ssl/cert.pem`, such as the one from [python-certifi](https://raw.githubusercontent.com/certifi/python-certifi/master/certifi/cacert.pem). Without this, you will face certificate errors.
* `procps-ng`: The `top` command depends on a terminfo database being available at `/etc/terminfo`, `/usr/lib/terminfo` or `/usr/share/terminfo`. Alternatively, use `ps`, `kill` and friends from the same package, which do not have this limitation.
