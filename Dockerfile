# Request Tracker (RT) for testing and development, not for production use.
# https://github.com/python-rt/docker-rt
#
# Build for a specific RT version:
#
#   docker build --build-arg RT_VERSION=6.0.4 --tag request-tracker:6.0.4 .
#
# RT_VERSION is either a release version (e.g. 6.0.4, 5.0.9), which is downloaded from Best Practical and verified
# with its GPG signature, or a branch of https://github.com/bestpractical/rt (e.g. stable, master).
#
# Based on https://github.com/netsandbox/docker-rt-base and https://github.com/netsandbox/docker-rt by Christian Loos.

ARG DEBIAN_TAG=trixie-slim
FROM debian:${DEBIAN_TAG}

ARG RT_VERSION=6.0.4
# fingerprint of the key in keys/bestpractical-rt.asc, which signs the RT releases
ARG RT_SIGNING_KEY=C49B372F2BF84A19011660270DF0A283FEAC80B2

LABEL org.opencontainers.image.title="Request Tracker ${RT_VERSION} for testing" \
      org.opencontainers.image.description="Request Tracker (RT) with SQLite for CI and local testing, not for production use" \
      org.opencontainers.image.version="${RT_VERSION}" \
      org.opencontainers.image.licenses="GPL-2.0-only" \
      org.opencontainers.image.source="https://github.com/python-rt/docker-rt" \
      org.opencontainers.image.url="https://github.com/python-rt/docker-rt"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update && apt-get -y install --no-install-recommends \
    ca-certificates \
    cpanminus \
    curl \
    gcc \
    gnupg \
    libc-dev \
    make \
    # HTML::Gumbo newer than the Debian package (required by RT 6.0.4) is built with the system libgumbo
    libgumbo-dev \
    pkg-config \
    # RT dependencies
    libapache-session-perl \
    libarchive-zip-perl \
    libbusiness-hours-perl \
    libcgi-emulate-psgi-perl \
    libcgi-psgi-perl \
    libconvert-color-perl \
    libcrypt-eksblowfish-perl \
    libcrypt-ssleay-perl \
    libcrypt-x509-perl \
    libcss-inliner-perl \
    libcss-minifier-xs-perl \
    libcss-squish-perl \
    libdata-guid-perl \
    libdata-ical-perl \
    libdata-page-pageset-perl \
    libdata-page-perl \
    libdate-extract-perl \
    libdate-manip-perl \
    libdatetime-format-natural-perl \
    libdatetime-set-perl \
    libdbd-sqlite3-perl \
    libdbix-searchbuilder-perl \
    libdevel-globaldestruction-perl \
    libemail-address-list-perl \
    libemail-address-perl \
    libencode-detect-perl \
    libencode-hanextra-perl \
    libencode-perl \
    libfile-sharedir-perl \
    libgd-graph-perl \
    libgnupg-interface-perl \
    libgraphviz2-perl \
    libhash-merge-extra-perl \
    libhash-merge-perl \
    libhtml-formatexternal-perl \
    libhtml-formattext-withlinks-andtables-perl \
    libhtml-formattext-withlinks-perl \
    libhtml-gumbo-perl \
    libhtml-mason-psgihandler-perl \
    libhtml-quoted-perl \
    libhtml-rewriteattributes-perl \
    libhtml-scrubber-perl \
    libhttp-message-perl \
    libimager-perl \
    libipc-run3-perl \
    libjavascript-minifier-xs-perl \
    libjson-perl \
    liblocale-maketext-fuzzy-perl \
    liblocale-maketext-lexicon-perl \
    liblog-dispatch-perl \
    libmailtools-perl \
    libmime-tools-perl \
    libmime-types-perl \
    libmodule-path-perl \
    libmodule-refresh-perl \
    libmodule-signature-perl \
    libmodule-versions-report-perl \
    libmoose-perl \
    libmoosex-nonmoose-perl \
    libmoosex-role-parameterized-perl \
    libmozilla-ca-perl \
    libnet-cidr-perl \
    libnet-ip-perl \
    libnet-ldap-perl \
    libparallel-forkmanager-perl \
    libpath-dispatcher-perl \
    libperlio-eol-perl \
    libplack-perl \
    libregexp-common-net-cidr-perl \
    libregexp-common-perl \
    libregexp-ipv6-perl \
    librole-basic-perl \
    libscope-upper-perl \
    libsymbol-global-name-perl \
    libterm-readkey-perl \
    libtext-password-pronounceable-perl \
    libtext-quoted-perl \
    libtext-template-perl \
    libtext-wikiformat-perl \
    libtext-worddiff-perl \
    libtext-wrapper-perl \
    libtime-parsedate-perl \
    libtree-simple-perl \
    libuniversal-require-perl \
    libweb-machine-perl \
    libxml-rss-perl \
    perl-doc \
    starlet \
    w3m \
  && rm -rf /var/lib/apt/lists/*

# RT dependencies which are not packaged by Debian or too old there
RUN cpanm --notest DBIx::SearchBuilder Pod::Select Time::ParseDate \
  && cpanm --notest --force CSS::Inliner \
  && rm -rf /root/.cpanm

COPY keys/bestpractical-rt.asc /usr/local/share/rt-docker/

WORKDIR /usr/local/src

# the mode of mkdir only applies to the gpg and smime directories, as intended
# hadolint ignore=DL3003,SC2174
RUN if [[ "$RT_VERSION" =~ ^[0-9] ]]; then \
      if [[ "$RT_VERSION" =~ (alpha|beta|rc) ]]; then release_dir=devel; else release_dir=release; fi; \
      url="https://download.bestpractical.com/pub/rt/${release_dir}/rt-${RT_VERSION}.tar.gz"; \
      curl -fsSL -o rt.tar.gz "$url" \
      && curl -fsSL -o rt.tar.gz.asc "${url}.asc" \
      && export GNUPGHOME="$(mktemp -d)" \
      && gpg --batch --import /usr/local/share/rt-docker/bestpractical-rt.asc \
      && gpg --batch --status-fd 1 --verify rt.tar.gz.asc rt.tar.gz | grep -q "^\[GNUPG:\] VALIDSIG ${RT_SIGNING_KEY} " \
      && rm -rf "$GNUPGHOME"; \
    else \
      curl -fsSL -o rt.tar.gz "https://github.com/bestpractical/rt/archive/refs/heads/${RT_VERSION}.tar.gz"; \
    fi \
  && tar -xzf rt.tar.gz \
  && cd rt-* \
  # a git checkout has no version, configure takes it from .tag
  && if [[ ! "$RT_VERSION" =~ ^[0-9] ]]; then echo "rt-${RT_VERSION}.$(date -I)" > .tag; fi \
  && if [[ "$RT_VERSION" =~ ^[45]\. ]]; then gd_option=--enable-gd; else gd_option=; fi \
  && ./configure.ac \
    --prefix=/opt/rt \
    --enable-externalauth \
    --enable-gpg \
    --enable-graphviz \
    --enable-smime \
    $gd_option \
    --with-db-type=SQLite \
    --with-web-handler=standalone \
  # install missing dependencies (e.g. of unreleased branches) and fail if any are still missing
  && RT_FIX_DEPS_CMD="cpanm --notest" make fixdeps \
  && make testdeps \
  && rm -rf /root/.cpanm \
  && make install \
  && mkdir --mode=0700 --parents /opt/rt/var/data/gpg /opt/rt/var/data/smime \
  && make initialize-database \
  && cd .. && rm -rf /usr/local/src/*

WORKDIR /opt/rt

COPY docker-entrypoint.sh bin/* /usr/local/bin/

ENV RT_WEB_PORT=8080
EXPOSE 8080

# lets GitHub Actions service containers wait until RT answers; shell form to expand RT_WEB_PORT
# hadolint ignore=DL3025
HEALTHCHECK --interval=5s --timeout=5s --start-period=60s --start-interval=1s --retries=3 \
  CMD curl -fsS -o /dev/null "http://localhost:${RT_WEB_PORT}/" || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/opt/rt/sbin/rt-server"]
