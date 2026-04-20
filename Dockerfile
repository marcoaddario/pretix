# =============================================================================
# Hardened pretix standalone image with custom plugins
#
# Base image:  python:3.13-slim-bookworm
#   - Replaces python:3.11-bookworm used by upstream
#   - Python 3.13 removes known CVEs present in 3.11
#   - Debian 12 "Bookworm" (stable, glibc-based, fully patched)
#   - "slim" variant removes ~200 MB of documentation / locales cruft
#
# Compatibility: 100% compatible with pretix/standalone:stable
#   - Same UID/GID for pretixuser (15371)
#   - Same VOLUME declarations  : /etc/pretix  /data
#   - Same EXPOSE               : 80
#   - Same ENTRYPOINT / CMD     : pretix all | web | taskworker
#   - Same ENV vars             : LC_ALL, DJANGO_SETTINGS_MODULE
#
# Custom plugins:
#   - Listed in pretix-plugins.txt (one pip package per line)
#   - Installed from source before make production is called,
#     so assets are compiled with plugins already present in one pass
# =============================================================================

ARG PYTHON_BASE=python:3.13-slim-bookworm

FROM ${PYTHON_BASE}

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        gettext \
        git \
        libffi-dev \
        libjpeg-dev \
        libmemcached-dev \
        libpq-dev \
        libssl-dev \
        libxml2-dev \
        libxslt1-dev \
        locales \
        nginx \
        nodejs \
        npm \
        python3-dev \
        python3-virtualenv \
        sudo \
        supervisor \
        libmaxminddb0 \
        libmaxminddb-dev \
        zlib1g-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    locale-gen C.UTF-8 && \
    /usr/sbin/update-locale LANG=C.UTF-8 && \
    mkdir /etc/pretix && \
    mkdir /data && \
    useradd -ms /bin/bash -d /pretix -u 15371 pretixuser && \
    echo 'pretixuser ALL=(ALL) NOPASSWD:SETENV: /usr/bin/supervisord' >> /etc/sudoers && \
    mkdir /static && \
    mkdir /etc/supervisord

# ── Environment ───────────────────────────────────────────────────────────────
ENV LC_ALL=C.UTF-8 \
    DJANGO_SETTINGS_MODULE=production_settings

# ── Copy configuration / helper files from the checked-out pretix source ─────
# The GitHub Action clones github.com/pretix/pretix before docker build,
# so these paths exist in the build context at CI time.
COPY deployment/docker/pretix.bash              /usr/local/bin/pretix
COPY deployment/docker/supervisord              /etc/supervisord
COPY deployment/docker/supervisord.all.conf     /etc/supervisord.all.conf
COPY deployment/docker/supervisord.web.conf     /etc/supervisord.web.conf
COPY deployment/docker/nginx.conf               /etc/nginx/nginx.conf
COPY deployment/docker/nginx-max-body-size.conf /etc/nginx/conf.d/nginx-max-body-size.conf
COPY deployment/docker/production_settings.py   /pretix/src/production_settings.py

# ── Copy Python package source ────────────────────────────────────────────────
COPY pyproject.toml /pretix/pyproject.toml
COPY _build         /pretix/_build
COPY src            /pretix/src

# ── Install core Python dependencies ─────────────────────────────────────────
RUN pip3 install -U \
        pip \
        setuptools \
        wheel && \
    cd /pretix && \
    PRETIX_DOCKER_BUILD=TRUE pip3 install \
        -e ".[memcached]" \
        gunicorn django-extensions ipython && \
    rm -rf ~/.cache/pip

# ── Install custom plugins ────────────────────────────────────────────────────
# pretix-plugins.txt lists one pip-installable package per line, e.g.:
#   pretix-passbook
#   pretix-pages
#   git+https://github.com/some/plugin.git
#
# Plugins are installed BEFORE make production so that their static assets
# (JS/CSS bundles) are compiled together with the core in a single pass —
# the same pattern used in the official pretix plugin documentation.
COPY pretix-plugins.txt /tmp/pretix-plugins.txt
RUN pip3 install --no-cache-dir -r /tmp/pretix-plugins.txt && \
    rm /tmp/pretix-plugins.txt

# ── Post-install setup ────────────────────────────────────────────────────────
RUN chmod +x /usr/local/bin/pretix && \
    rm /etc/nginx/sites-enabled/default && \
    cd /pretix/src && \
    rm -f pretix.cfg && \
    mkdir -p data && \
    chown -R pretixuser:pretixuser /pretix /data data && \
    sudo -u pretixuser make production

# ── Runtime configuration ─────────────────────────────────────────────────────
USER pretixuser

VOLUME ["/etc/pretix", "/data"]

EXPOSE 80

ENTRYPOINT ["pretix"]
CMD ["all"]