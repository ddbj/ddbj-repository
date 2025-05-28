# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t repository .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name repository repository

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.4
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    TZ="Japan"

FROM docker.io/library/ruby:$RUBY_VERSION-slim AS noodles_gff

ENV PATH="/root/.cargo/bin:${PATH}"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential clang curl && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

WORKDIR /noodles_gff-rb

COPY noodles_gff-rb/ .

RUN bundle install
RUN bundle exec rake compile

# Throw-away build stage to reduce size of final image
FROM base AS build

COPY --from=noodles_gff /noodles_gff-rb ./noodles_gff-rb

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config libyaml-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

FROM docker.io/library/node:22.16.0 AS web

ARG API_URL
ENV API_URL=${API_URL:?}

RUN corepack enable pnpm

WORKDIR /web

COPY web ./
COPY schema /schema

RUN pnpm install --frozen-lockfile
RUN pnpm build




# Final stage for app image
FROM base

ARG APP_UID
ARG APP_GID

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails
COPY --from=noodles_gff /noodles_gff-rb /rails/noodles_gff-rb
COPY --from=web /web/dist /rails/public/web

COPY schema /schema

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid ${APP_GID:?} rails && \
    useradd rails --uid ${APP_UID:?} --gid ${APP_GID:?} --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER ${APP_UID:?}:${APP_GID:?}

RUN bundle exec submission-excel2xml download_xsd

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
