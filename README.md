# Request Tracker container for testing

A container image of [Request Tracker (RT)](https://bestpractical.com/request-tracker) for CI and local testing of
RT clients and integrations, e.g. of the REST2 API. It can be built for any RT version and comes ready to use:
SQLite database, user `root` with password `password`, a health check, and helpers to create API tokens, users and
initial data.

**Not for production use:** the setup is insecure by design (known root password, SQLite, no TLS).

Based on [netsandbox/docker-rt-base](https://github.com/netsandbox/docker-rt-base) and
[netsandbox/docker-rt](https://github.com/netsandbox/docker-rt) by Christian Loos, consolidated into one image.

## Quick start

```shell
docker run -d --name rt -p 8080:8080 ghcr.io/python-rt/request-tracker:6.0.4

# REST2 with basic authentication
curl -u root:password http://localhost:8080/REST/2.0/rt

# create an API token
export RT_TOKEN=$(docker exec rt rt-token)
curl -H "Authorization: token $RT_TOKEN" http://localhost:8080/REST/2.0/rt
```

The web interface is available at <http://localhost:8080>. The container is healthy as soon as RT answers requests,
`docker ps` shows the state.

## Image tags

| Tag | RT version |
| --- | --- |
| `6.0.4`, `6.0`, `6`, `latest` | 6.0.4 |

## Configuration

| Environment variable | Default | Description |
| --- | --- | --- |
| `RT_WEB_PORT` | `8080` | Port RT listens on. RT uses it in the URLs it returns, so map the same port on the host (`-p 9000:9000 -e RT_WEB_PORT=9000`). |
| `RT_WEB_DOMAIN` | `localhost` | Host name RT uses in the URLs it returns ([WebDomain](https://docs.bestpractical.com/rt/latest/RT_Config.html#WebDomain)). |
| `RT_ROOT_PASSWORD` | | Password of the user `root`, set on the first start. Without it the password is `password`. |
| `RT_MAIL_COMMAND` | `testfile` | [MailCommand](https://docs.bestpractical.com/rt/latest/RT_Config.html#MailCommand); `testfile` writes outgoing mails into a file instead of sending them. |
| `RT_CANONICALIZE_REDIRECT_URLS` | `0` | [CanonicalizeRedirectURLs](https://docs.bestpractical.com/rt/latest/RT_Config.html#CanonicalizeRedirectURLs) |
| `RT_SECRET_KEY` | random | [SecretKey](https://docs.bestpractical.com/rt/latest/RT_Config.html#SecretKey); without it a random key is created on the first start and kept in `/opt/rt/var/secret-key`. |
| `RT_LOG_LEVEL` | `info` | Log level of the RT log on stderr (`docker logs`), e.g. `debug`, `warning`. |
| `RT_INIT_DIR` | `/docker-entrypoint-init.d` | Directory with initialization files, see below. |

The configuration is written to `/opt/rt/etc/RT_SiteConfig.d/00-docker.pm` on every start. Further RT configuration
can be mounted as file into the same directory, e.g. `-v ./my-config.pm:/opt/rt/etc/RT_SiteConfig.d/50-my-config.pm:ro`.

## Initialization

On the first start, before RT is started, the files in `/docker-entrypoint-init.d` are processed in alphabetical
order:

- `*.pl`: [RT initial data](https://docs.bestpractical.com/rt/latest/initialdata.html), e.g. users, groups,
  queues, custom fields (also applied to queues) and rights, see [examples/initialdata.pl](examples/initialdata.pl)
- `*.sh`: shell scripts, e.g. using the helpers below

```shell
docker run -d --name rt -p 8080:8080 -v ./examples:/docker-entrypoint-init.d:ro ghcr.io/python-rt/request-tracker:6.0.4
```

The initialization is not repeated when the container is restarted.

## Helpers

The helpers can be used in initialization scripts or with `docker exec` in a running container.

| Command | Description |
| --- | --- |
| `rt-token [--user NAME] [--description TEXT]` | Creates an [authentication token](https://docs.bestpractical.com/rt/latest/RT/Authen/Token.html) for the user (default `root`) and prints it. |
| `rt-user NAME [--password PASSWORD] [--email ADDRESS] [--real-name NAME] [--privileged \| --unprivileged] [--superuser \| --no-superuser]` | Creates a user (privileged by default) or updates an existing one. `--superuser` grants all rights. |
| `rt-initdata FILE` / `rt-initdata -` | Inserts initial data from a file or stdin. |

```shell
docker exec rt rt-user alice --password secret --email alice@example.com
export ALICE_TOKEN=$(docker exec rt rt-token --user alice)
docker exec -i rt rt-initdata - < examples/initialdata.pl
```

## Use in GitHub Actions

As service container: GitHub Actions waits until the container is healthy before running the steps.

```yaml
jobs:
  test:
    runs-on: ubuntu-latest

    services:
      rt:
        image: ghcr.io/python-rt/request-tracker:6.0.4
        ports:
          - 8080:8080

    steps:
      - uses: actions/checkout@v7

      - name: Prepare RT
        run: |
          docker exec "${{ job.services.rt.id }}" rt-user alice --password secret
          docker exec -i "${{ job.services.rt.id }}" rt-initdata - < tests/initialdata.pl
          echo "RT_TOKEN=$(docker exec "${{ job.services.rt.id }}" rt-token)" >> "$GITHUB_ENV"

      - name: Test
        run: ...
```

To test with several RT versions, use a matrix for the image tag.

## Build

```shell
docker build --build-arg RT_VERSION=6.0.4 --tag request-tracker:6.0.4 .
./test.sh request-tracker:6.0.4 6.0.4
```

`RT_VERSION` is either

- a release version, e.g. `6.0.4` or `5.0.9`: the release is downloaded from Best Practical and its GPG signature is
  verified with the key in [keys/bestpractical-rt.asc](keys/bestpractical-rt.asc) (fingerprint
  `C49B 372F 2BF8 4A19 0116 6027 0DF0 A283 FEAC 80B2`, the build fails for any other signature), or
- a branch of [bestpractical/rt](https://github.com/bestpractical/rt), e.g. `stable` or `master` (not verified).

Missing Perl dependencies of the version are installed from CPAN and the build fails if any are still missing.
`test.sh` starts a container of the image and checks the configuration, the helpers and the initialization.

The built versions and their image tags are listed in [versions.json](versions.json).

## New RT releases

The workflow *Check for RT releases* ([.github/workflows/update.yml](.github/workflows/update.yml)) checks the
[releases](https://download.bestpractical.com/pub/rt/release/) daily:

- a new release of a built series (e.g. 6.0.5 for 6.0.4) gets a pull request, which updates `versions.json`, the
  `Dockerfile` default and this README; the image is built and tested on it and published when it is merged,
- a new series (e.g. 6.1 or 7.0) gets an issue, as the tags to move (e.g. `latest`) and whether to keep building the
  previous series are a decision; this is done by hand in `versions.json`.

Each update gets one pull request and each new series one issue, also if it is closed without merging or doing
anything; pull requests and issues are not opened again on the following runs. The workflow needs the repository setting *Allow GitHub Actions to create and approve pull requests*
(Settings, Actions, General).

The update can also be done locally with `scripts/rt-release.py check` and `scripts/rt-release.py apply OLD NEW`.

If the build of a new release fails at the signature check, Best Practical has signed it with another key: replace
[keys/bestpractical-rt.asc](keys/bestpractical-rt.asc) and the fingerprint in `RT_SIGNING_KEY` of the `Dockerfile` and
above, after verifying the new key.

## Publishing

The workflow builds and tests every pull request. On `main`, and weekly to pick up Debian updates, it also publishes
the images to `ghcr.io/python-rt/request-tracker`:

1. each RT version is built for `linux/amd64`, tested with `test.sh` and pushed with its tags,
2. the image is signed with [cosign](https://docs.sigstore.dev/cosign/) (keyless, with the identity of the workflow),
3. the images which are no longer tagged, i.e. the previous builds, are deleted together with their signatures, so
   only the current build is kept (GitHub has no setting for this).

The cleanup uses `GITHUB_TOKEN`, which may only delete images if the repository has the role *Admin* on the package
(package settings, *Manage Actions access*). The repository gets this role automatically when its workflow creates the
package; it only has to be granted if the package was created otherwise.

### Verify the signature

```shell
cosign verify ghcr.io/python-rt/request-tracker:6.0.4 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity https://github.com/python-rt/docker-rt/.github/workflows/build.yml@refs/heads/main
```

## License

GPL-2.0, like the projects this is based on, see [COPYING](COPYING).
