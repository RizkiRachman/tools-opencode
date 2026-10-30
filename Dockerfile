FROM node:22-bookworm-slim

ARG OPENCODE_VERSION=1.19.0
ARG GRAPHIFY_VERSION=0.8.49
ARG LEAN_CTX_VERSION=3.10.2
ARG CONTEXT7_VERSION=4.4.1
ARG MCP_MEMORY_VERSION=2.0.1
ARG MCP_EVERYTHING_VERSION=2.1.0

# Corporate CA certificates.
# Place PEM certificates with the .crt extension under certs/.
COPY certs/ /usr/local/share/ca-certificates/

# Base packages. The optional `preinstall` additional build context (/pi, see
# docker-compose files) pre-seeds cached .deb files so repeat builds skip most
# downloads; the apt cache mounts keep downloaded state out of the image layer.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=from=preinstall,src=/,dst=/pi,ro \
    set -eux; \
    [ -n "$(ls /pi/apt/*.deb 2>/dev/null)" ] && dpkg -i /pi/apt/*.deb || true; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      git \
      curl \
      jq \
      ripgrep \
      ca-certificates \
      python3 \
      pipx \
      python3-venv \
      coreutils \
      procps; \
    update-ca-certificates; \
    git config --system --add safe.directory '*'

# Configure Node.js and Python to trust the corporate CA.
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    PIP_CERT=/etc/ssl/certs/ca-certificates.crt

# Locale + terminal defaults so the TUI and ncurses apps render correctly in
# `docker exec -it` sessions (which inherit the container env, not the host's).
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color

# Install OpenCode and the Context7 MCP server.
# Context7 is baked (not npx) so library docs lookup works on
# offline / CA-restricted corporate networks without a runtime download.
# Tarball-first from the offline store (/pi/npm), network as fallback.
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    --mount=from=preinstall,src=/,dst=/pi,ro \
    set -eux; \
    if ls /pi/npm/opencode-ai-*.tgz >/dev/null 2>&1; then \
      npm install -g --offline --no-audit --no-fund /pi/npm/opencode-ai-*.tgz \
        || npm install -g --no-audit --no-fund /pi/npm/opencode-ai-*.tgz; \
    else \
      npm install -g --no-audit --no-fund "opencode-ai@${OPENCODE_VERSION}"; \
    fi; \
    if ls /pi/npm/@upstash+context7-mcp-*.tgz >/dev/null 2>&1; then \
      npm install -g --offline --no-audit --no-fund /pi/npm/@upstash+context7-mcp-*.tgz \
        || npm install -g --no-audit --no-fund /pi/npm/@upstash+context7-mcp-*.tgz; \
    else \
      npm install -g --no-audit --no-fund "@upstash/context7-mcp@${CONTEXT7_VERSION}"; \
    fi; \
    opencode --version; \
    command -v context7-mcp

# lean-ctx binary: from the offline store when present, else upstream installer.
RUN --mount=from=preinstall,src=/,dst=/pi,ro \
    set -eux; \
    if [ -f /pi/bin/lean-ctx ]; then \
      install -m 0755 /pi/bin/lean-ctx /usr/local/bin/lean-ctx; \
    else \
      curl -fsSL \
        "https://raw.githubusercontent.com/yvgude/lean-ctx/v${LEAN_CTX_VERSION}/install.sh" \
        -o /tmp/leanctx-install.sh; \
      chmod +x /tmp/leanctx-install.sh; \
      LEAN_CTX_NO_ONBOARD=1 sh /tmp/leanctx-install.sh --download; \
      install -m 0755 /root/.local/bin/lean-ctx /usr/local/bin/lean-ctx; \
      rm -rf /root/.local /tmp/leanctx-install.sh; \
    fi; \
    lean-ctx --version

# Install Graphify and its MCP server (wheel-first from the offline store).
ENV PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin

RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    --mount=from=preinstall,src=/,dst=/pi,ro \
    set -eux; \
    if ls /pi/pip/graphifyy-*.whl >/dev/null 2>&1; then \
      PIP_FIND_LINKS=/pi/pip PIP_NO_INDEX=true pipx install /pi/pip/graphifyy-*.whl; \
      PIP_FIND_LINKS=/pi/pip PIP_NO_INDEX=true pipx inject graphifyy /pi/pip/mcp-*.whl; \
    else \
      pipx install "graphifyy[mcp]==${GRAPHIFY_VERSION}"; \
      pipx inject graphifyy "mcp<2"; \
    fi; \
    graphify --help >/dev/null; \
    command -v graphify-mcp

# Memory + everything MCP servers and the fetch MCP server,
# tarball/wheel-first from the offline store, network as fallback.
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    --mount=from=preinstall,src=/,dst=/pi,ro \
    set -eux; \
    if ls /pi/npm/@modelcontextprotocol+server-memory-*.tgz >/dev/null 2>&1; then \
      npm install -g --offline --no-audit --no-fund /pi/npm/@modelcontextprotocol+server-memory-*.tgz \
        || npm install -g --no-audit --no-fund /pi/npm/@modelcontextprotocol+server-memory-*.tgz; \
    else \
      npm install -g --no-audit --no-fund "@modelcontextprotocol/server-memory@${MCP_MEMORY_VERSION}"; \
    fi; \
    if ls /pi/npm/@modelcontextprotocol+server-everything-*.tgz >/dev/null 2>&1; then \
      npm install -g --offline --no-audit --no-fund /pi/npm/@modelcontextprotocol+server-everything-*.tgz \
        || npm install -g --no-audit --no-fund /pi/npm/@modelcontextprotocol+server-everything-*.tgz; \
    else \
      npm install -g --no-audit --no-fund "@modelcontextprotocol/server-everything@${MCP_EVERYTHING_VERSION}"; \
    fi; \
    if ls /pi/pip/mcp_server_fetch-*.whl >/dev/null 2>&1; then \
      PIP_FIND_LINKS=/pi/pip PIP_NO_INDEX=true pipx install /pi/pip/mcp_server_fetch-*.whl; \
    else \
      pipx install mcp-server-fetch; \
    fi

# Prepare OpenCode configuration and persistent-data directories.
RUN mkdir -p \
      /home/node/.config/opencode \
      /home/node/.local/share/opencode \
      /home/node/workspace \
 && chown -R node:node /home/node

# Install the entrypoint and normalize Windows CRLF line endings.
# (Placed before COPY engine/ so engine edits don't invalidate these layers.)
COPY entrypoint.sh /usr/local/bin/opencode-entrypoint.sh

RUN sed -i 's/\r$//' /usr/local/bin/opencode-entrypoint.sh \
 && chmod 755 /usr/local/bin/opencode-entrypoint.sh

USER node

# Pre-install only the plugins enabled in opencode.json.
# - model-fallback: executor -> reviewer fallback for cross-model review.
# - @tarquinen/opencode-dcp: prunes obsolete tool outputs to cut token usage
#   on long multi-agent runs (paired with compaction in opencode.json).
# - opencode-websearch-cited: grounded websearch with citations. Requires an
#   OpenAI or Google provider auth to actually fire; inert otherwise.
# Installs into ~/.config/opencode/node_modules; opencode.json references them
# by file:// path in the plugin[] array.
# Tarball-first from the offline store (/pi/npm), network as fallback.
RUN --mount=type=cache,target=/home/node/.npm,sharing=locked,uid=1000,gid=1000 \
    --mount=from=preinstall,src=/,dst=/pi,ro \
    set -eux; \
    plugin_install() { \
      if ls $1 >/dev/null 2>&1; then \
        npm install --offline --no-audit --no-fund $1 \
          || npm install --no-audit --no-fund $1; \
      else \
        npm install --no-audit --no-fund "$2"; \
      fi; \
    }; \
    cd /home/node/.config/opencode; \
    plugin_install '/pi/npm/@opencode-ai+plugin-*.tgz' '@opencode-ai/plugin@1.19.0'; \
    plugin_install '/pi/npm/@razroo+opencode-model-fallback-*.tgz' '@razroo/opencode-model-fallback@0.3.2'; \
    plugin_install '/pi/npm/@tarquinen+opencode-dcp-*.tgz' '@tarquinen/opencode-dcp@3.2.0'; \
    plugin_install '/pi/npm/opencode-websearch-cited-*.tgz' 'opencode-websearch-cited@1.2.0'

# Copy the shared workflow engine. (Kept LAST: engine edits only invalidate
# the layers below, not the package installs above.)
ENV ENGINE_ROOT=/opt/engine

# Engine transform needs root: removes root-owned files, chowns, sets exec bits
USER root

COPY engine/ /opt/engine/

RUN set -eux; \
    rm -f /opt/engine/.env /opt/engine/.env.template; \
    find /opt/engine -type f \( \
        -name '*.sh' \
        -o -name '*.md' \
        -o -name '*.json' \
        -o -name '*.js' \
        -o -name '*.mjs' \
        -o -name '*.ts' \
      \) -exec sed -i 's/\r$//' {} +; \
    if [ -d /opt/engine/.githooks ]; then \
      find /opt/engine/.githooks \
        -type f \
        -exec sed -i 's/\r$//' {} + \
        -exec chmod a+x {} +; \
    fi; \
    find /opt/engine -name '*.md' \
      -exec sed -E -i \
        -e 's#\.opencode/(agents|skills|rules|usage|contract)/#/opt/engine/\1/#g' \
        -e 's#([` (])(\.\./|\./)?(scripts|contract|rules|agents|usage|skills|doc|templates)/#\1/opt/engine/\3/#g' \
        {} +; \
    find /opt/engine -name '*.sh' -exec chmod a+x {} +; \
    chown -R node:node /opt/engine; \
    ln -sfn /opt/engine/agent.md \
      /home/node/.config/opencode/agent.md; \
    ln -sfn /opt/engine/agents \
      /home/node/.config/opencode/agents; \
    ln -sfn /opt/engine/skills \
      /home/node/.config/opencode/skills; \
    ln -sfn /opt/engine/commands \
      /home/node/.config/opencode/command; \
    ln -sfn /opt/engine/rules \
      /home/node/.config/opencode/rules; \
    ln -sfn /opt/engine/contract \
      /home/node/.config/opencode/contract; \
    ln -sfn /opt/engine/usage \
      /home/node/.config/opencode/usage; \
    ln -sfn /opt/engine/doc \
      /home/node/.config/opencode/doc

# Drop back to the runtime user; nothing below needs root.
USER node

WORKDIR /home/node/workspace

ENTRYPOINT ["/usr/local/bin/opencode-entrypoint.sh"]

CMD ["opencode", "web", "--hostname", "0.0.0.0", "--port", "4096"]
