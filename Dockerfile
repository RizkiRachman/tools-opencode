FROM node:22-bookworm-slim

ARG OPENCODE_VERSION=latest
ARG GRAPHIFY_VERSION=0.8.49
ARG LEAN_CTX_VERSION=3.10.2
ARG CONTEXT7_VERSION=4.4.1

# Corporate CA certificates.
# Place PEM certificates with the .crt extension under certs/.
COPY certs/ /usr/local/share/ca-certificates/

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git \
      curl \
      jq \
      ripgrep \
      ca-certificates \
      python3 \
      pipx \
      python3-venv \
      coreutils \
      procps \
 && update-ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*'

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
RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" \
      "@upstash/context7-mcp@${CONTEXT7_VERSION}" \
 && opencode --version \
 && command -v context7-mcp

RUN curl -fsSL \
      "https://raw.githubusercontent.com/yvgude/lean-ctx/v${LEAN_CTX_VERSION}/install.sh" \
      -o /tmp/leanctx-install.sh \
 && chmod +x /tmp/leanctx-install.sh \
 && LEAN_CTX_NO_ONBOARD=1 \
      sh /tmp/leanctx-install.sh --download \
 && install -m 0755 /root/.local/bin/lean-ctx /usr/local/bin/lean-ctx \
 && rm -rf /root/.local /tmp/leanctx-install.sh \
 && lean-ctx --version


# Install Graphify and its MCP server.
ENV PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin

RUN pipx install "graphifyy[mcp]==${GRAPHIFY_VERSION}" \
 && pipx inject graphifyy "mcp<2" \
 && graphify --help >/dev/null \
 && command -v graphify-mcp

RUN npm install -g \
      @modelcontextprotocol/server-memory \
      @modelcontextprotocol/server-everything \
 && pipx install mcp-server-fetch

# Prepare OpenCode configuration and persistent-data directories.
RUN mkdir -p \
      /home/node/.config/opencode \
      /home/node/.local/share/opencode \
      /home/node/workspace \
 && chown -R node:node /home/node

# Copy the shared workflow engine.
ENV ENGINE_ROOT=/opt/engine

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
    ln -sfn /opt/engine/rules \
      /home/node/.config/opencode/rules; \
    ln -sfn /opt/engine/contract \
      /home/node/.config/opencode/contract; \
    ln -sfn /opt/engine/usage \
      /home/node/.config/opencode/usage; \
    ln -sfn /opt/engine/doc \
      /home/node/.config/opencode/doc

# Install the entrypoint and normalize Windows CRLF line endings.
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
RUN cd /home/node/.config/opencode \
 && npm install --no-audit --no-fund \
      "@opencode-ai/plugin@1.19.0" \
      @razroo/opencode-model-fallback@0.3.2 \
      @tarquinen/opencode-dcp@3.2.0 \
      opencode-websearch-cited@1.2.0

WORKDIR /home/node/workspace

ENTRYPOINT ["/usr/local/bin/opencode-entrypoint.sh"]

CMD ["opencode", "web", "--hostname", "0.0.0.0", "--port", "4096"]