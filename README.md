# static-builds

Statically-built, dependency free binaries of software packages for Linux. Just extract the binaries, add to your system, and run them!

Perfect for servers with limited installation capabilties (e.g. recovery situations), containerized environments or CI runners where pulling in a binary dependency with multiple files may not be possible.

In Golang, it is possible to create an executable that works on the target OS and architecture without having any other dependencies, ensuring that the only thing you need to run your software is to deploy the single binary in the server or container. This project aims to create a similar experience for other software packages.

## Installation

Head over to the [releases](https://github.com/supriyo-biswas/static-builds/releases) to download the binaries.

Some binaries have some special requirements:

* `curl`/`wget`/`git`: To download HTTPS content, you need to add a certificate bundle into `/etc/ssl/cert.pem`, such as the one from [python-certifi](https://raw.githubusercontent.com/certifi/python-certifi/master/certifi/cacert.pem). Without this, you will face certificate errors.
* `procps-ng`: The `top` command depends on a terminfo database being available at `/etc/terminfo`, `/usr/lib/terminfo` or `/usr/share/terminfo`. Alternatively, use `ps`, `kill` and friends from the same package, which do not have this limitation.

## Making releases

The `make-release.yml` workflow builds and tests one project at the requested Git
revision. By default it is a dry run: the resulting archives are available as a
workflow artifact for seven days, but no tag or GitHub release is created.

```sh
gh workflow run make-release.yml \
    --ref master \
    -f project=gzip \
    -f arch=all \
    -f publish=false
```

Set `publish=true` to create a tag and release. The version normally comes from
the project's `build.sh`; `override_version` changes only the tag and release
label, which is useful for testing the complete publishing path without moving
an existing production tag.

```sh
gh workflow run make-release.yml \
    --ref master \
    -f project=gzip \
    -f arch=all \
    -f override_version=1.15-test.1 \
    -f prerelease=true \
    -f publish=true
```

After checking a test release, delete both it and its tag with:

```sh
gh release delete gzip-1.15-test.1 --cleanup-tag --yes
```

For a normal release, omit `override_version`, set `prerelease=false`, and set
`publish=true`. Publishing fails without changing anything if the derived tag
already exists.

The `arch` input accepts `all`, `amd64`, or `arm64`. Selecting `all` runs the
two builds in parallel on native x64 and ARM64 GitHub-hosted runners. The build
scripts accept the same selection locally through the `ARCH` environment
variable, for example `ARCH=amd64 ./gzip/build.sh`.
