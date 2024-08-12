# syntax = docker/dockerfile:1

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t my-app .
# docker run -d -p 80:80 -p 443:443 --name my-app -e RAILS_MASTER_KEY=<value from config/master.key> my-app

ARG NODE_VERSION
ARG RUBY_VERSION

FROM docker.io/library/ruby:$RUBY_VERSION-slim as noodles_gff

ENV PATH="/root/.cargo/bin:${PATH}"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential clang curl && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

WORKDIR /app/noodles_gff-rb

COPY noodles_gff-rb/ .

RUN bundle install
RUN bundle exec rake compile

FROM docker.io/library/node:${NODE_VERSION:?} as web

ARG API_URL
ENV API_URL=${API_URL:?}

WORKDIR /app/web

COPY web ./
COPY schema /app/schema

RUN corepack enable pnpm
RUN pnpm install --frozen-lockfile
RUN pnpm build

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /app/api

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    TZ=Japan

# Throw-away build stage to reduce size of final image
FROM base as build

COPY --from=noodles_gff /app/noodles_gff-rb /app/noodles_gff-rb

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY api/Gemfile api/Gemfile.lock api/.ruby-version ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY api/ .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/




# Final stage for app image
FROM base

ARG APP_GID
ARG APP_UID

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /app/api /app/api
COPY --from=noodles_gff /app/noodles_gff-rb /app/noodles_gff-rb
COPY --from=web /app/web/dist /app/api/public/web

COPY schema /app/schema

# Run and own only the runtime files as a non-root user for security
RUN mkdir /.local
RUN chown -R ${APP_UID:?}:${APP_GID:?} db log tmp /.local
USER ${APP_UID:?}:${APP_GID:?}

RUN bundle exec submission-excel2xml download_xsd

# Entrypoint prepares the database.
ENTRYPOINT ["/app/api/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/rails", "server"]
