FROM ghcr.io/actions/actions-runner
# SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV type full
ENV CONTAINER shivammathur/node
ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_VERSION 18.17.1
ENV NODE_VERSION_x86 18.17.1
ENV YARN_VERSION 1.22.19
ENV RUNNER_TOOL_PATH "/opt/hostedtoolcache"
ENV RUNNER_TOOL_CACHE "/opt/hostedtoolcache"
ENV GITHUB_ENV "/tmp/set_env"
ENV GITHUB_PATH "/tmp/add_path"
ENV runner "self-hosted"

USER root

RUN ARCH= && MULTILIB= && PREFIX='www' && URLPATH='dist' && dpkgArch="$(dpkg --print-architecture)" \
  && case "${dpkgArch##*-}" in \
    amd64) ARCH='x64';; \
    ppc64el) ARCH='ppc64le';; \
    s390x) ARCH='s390x';; \
    arm64) ARCH='arm64';; \
    armhf) ARCH='armv7l';; \
    i386) ARCH='x86'; MULTILIB='gcc-multilib'; PREFIX='unofficial-builds'; URLPATH='download/release'; NODE_VERSION=$NODE_VERSION_x86;; \
    *) echo "unsupported architecture"; exit 1 ;; \
  esac \
  && set -ex \
  && echo "" | tee "$GITHUB_ENV" "$GITHUB_PATH" \
  && mkdir -p "$RUNNER_TOOL_CACHE" \
  # libatomic1 for arm
  && apt-get update && apt-get install -y ca-certificates curl wget gnupg dirmngr xz-utils libatomic1 $MULTILIB --no-install-recommends \
  # for gh start
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && apt-get update && apt-get install -y gh --no-install-recommends \
  # for gh end
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSLO --compressed "https://$PREFIX.nodejs.org/$URLPATH/v$NODE_VERSION/node-v$NODE_VERSION-linux-$ARCH.tar.xz" \
  && tar -xJf "node-v$NODE_VERSION-linux-$ARCH.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
  && rm "node-v$NODE_VERSION-linux-$ARCH.tar.xz" \
  && curl -o /usr/local/bin/spc -sL https://github.com/shivammathur/spc/releases/latest/download/spc \
  && curl -o /usr/local/bin/systemctl -sL https://raw.githubusercontent.com/shivammathur/node-docker/main/systemctl-shim \
  && chmod a+x /usr/local/bin/spc /usr/local/bin/systemctl \
  && apt-mark auto '.*' > /dev/null \
  && apt-mark manual curl libatomic1 $MULTILIB \
  && find /usr/local -type f -executable -exec ldd '{}' ';' \
    | awk '/=>/ { print $(NF-1) }' \
    | sort -u \
    | xargs -r dpkg-query --search \
    | cut -d: -f1 \
    | sort -u \
    | xargs -r apt-mark manual \
  && ln -s /usr/local/bin/node /usr/local/bin/nodejs \
  # smoke tests
  && node --version \
  && npm --version \
  && spc -V \
  && mkdir -p "/home/runner/.npm" \
  # fix: publish firebase hosting
  && chown -R runner:runner "/home/runner/.npm"


RUN set -ex \
  && savedAptMark="$(apt-mark showmanual)" \
  && apt-get update && apt-get install -y ca-certificates curl wget gnupg dirmngr make sudo --no-install-recommends \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSLO --compressed "https://github.com/yarnpkg/yarn/releases/download/v$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
  && mkdir -p /opt /opt/hostedtoolcache \
  && chmod -R 777 /opt/hostedtoolcache \
  && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/ \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarn /usr/local/bin/yarn \
  && ln -s /opt/yarn-v$YARN_VERSION/bin/yarnpkg /usr/local/bin/yarnpkg \
  && rm yarn-v$YARN_VERSION.tar.gz \
  && apt-mark auto '.*' > /dev/null \
  && apt-mark manual ca-certificates sudo make \
  && { [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; } \
  && find /usr/local -type f -executable -exec ldd '{}' ';' \
    | awk '/=>/ { print $(NF-1) }' \
    | sort -u \
    | xargs -r dpkg-query --search \
    | cut -d: -f1 \
    | sort -u \
    | xargs -r apt-mark manual \
  # smoke test
  && yarn --version

RUN if [ "$type" = "full" ]; then set -ex \
      && savedAptMark="$(apt-mark showmanual)" \
      && apt-mark auto '.*' > /dev/null \
      && apt-get update && apt-get install -y --no-install-recommends curl gnupg jq lsb-release mysql-server postgresql software-properties-common unzip \
      && usermod -d /var/lib/mysql/ mysql \
      && add-apt-repository ppa:git-core/ppa -y \
      && LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/php \
      && apt-get remove software-properties-common -y \
      && apt-get update \
      && cp -r /etc/apt/sources.list.d /etc/apt/sources.list.d.save \
      && for v in 5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2; do \
           apt-get install -y --no-install-recommends php"$v" \
           php"$v"-dev \
           php"$v"-curl \
           php"$v"-mbstring \
           php"$v"-xml \
           php"$v"-intl \
           php"$v"-mysql \
           php"$v"-pgsql \
           php"$v"-xdebug \
           php"$v"-zip; \
         done \
      && curl -o /usr/bin/systemctl -sL https://raw.githubusercontent.com/shivammathur/node-docker/main/systemctl-shim \
      && chmod a+x /usr/bin/systemctl \
      && curl -o /usr/lib/ssl/cert.pem -sL https://curl.se/ca/cacert.pem \
      && curl -o /tmp/pear.phar -sL https://raw.githubusercontent.com/pear/pearweb_phars/master/install-pear-nozlib.phar \
      && php /tmp/pear.phar && rm -f /tmp/pear.phar \
      && apt-get install -y --no-install-recommends autoconf automake gcc g++ git \
      && rm -rf /var/lib/apt/lists/* \
      && { [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; } \
      && find /usr/local -type f -executable -exec ldd '{}' ';' \
        | awk '/=>/ { print $(NF-1) }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual \
      # smoke test
      && gcc --version \
      && g++ --version \
      && git --version \
      && php5.6 -v \
      && php7.0 -v \
      && php7.1 -v \
      && php7.2 -v \
      && php7.3 -v \
      && php7.4 -v \
      && php8.0 -v \
      && php8.1 -v \
      && php8.2 -v \
      && php -v; \
    fi

USER runner
