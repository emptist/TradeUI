# ================================
# Build image
# ================================
# docker build -t trade-cli .
# ================================
# Run with Strategy File
# ================================
# docker run --rm \
#   -v $(pwd)/strategy.so:/strategy.so \
#   trade-cli /strategy.so FUT ESM5 60 CME USD
# ================================
# Replace $(pwd)/strategy.so with the actual path to your compiled .so
#

# Build stage: compile the CLI tool
FROM swift:6.1-jammy as builder

WORKDIR /app

# Clone TradeUI CLI tool
RUN git clone https://github.com/TradeWithIt/TradeUI.git .

WORKDIR /app/Trade

# Build the CLI executable
RUN swift build -c release --product trade

# Runtime stage: minimal Ubuntu with shared lib support
FROM ubuntu:22.04

# Install required shared lib dependencies
RUN apt-get update && apt-get install -y \
    libicu-dev \
    libcurl4-openssl-dev \
    libxml2 \
    libz-dev \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy the CLI binary from the build stage
COPY --from=builder /app/.build/release/trade /usr/local/bin/trade

# Default entrypoint is the CLI
ENTRYPOINT ["trade"]
