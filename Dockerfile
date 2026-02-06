# Multi-stage build for Claude Code Mux
# Stage 1: Build
FROM rust:1.83-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copy source code
COPY . .

# Build the application
RUN cargo build --release && \
    strip /build/target/release/ccm

# Stage 2: Runtime
FROM debian:bookworm-slim

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Create app user and directories
RUN groupadd -g 1000 ccm && \
    useradd -d /home/ccm -s /sbin/nologin -u 1000 -g ccm ccm && \
    mkdir -p /app/config /home/ccm/.claude-code-mux && \
    chown -R ccm:ccm /app /home/ccm/.claude-code-mux

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/target/release/ccm /app/ccm

# Copy config templates
COPY --from=builder /build/config ./config-templates

# Set proper permissions
RUN chmod +x /app/ccm && \
    chown -R ccm:ccm /app

# Switch to non-root user
USER ccm

# Environment variables
ENV CCM_CONFIG=/home/ccm/.claude-code-mux/config.toml \
    CCM_HOST=0.0.0.0 \
    CCM_PORT=13456 \
    RUST_LOG=info

# Expose port
EXPOSE 13456

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:13456/api/config/json || exit 1

# Run the application
CMD ["sh", "-c", \
     "[ -f $CCM_CONFIG ] || cp /app/config-templates/default.example.toml $CCM_CONFIG 2>/dev/null || true; \
     /app/ccm start --config $CCM_CONFIG"]