# syntax = docker/dockerfile:1

ARG NODE_VERSION
ARG RUBY_VERSION

FROM node:${NODE_VERSION:?} as web

ARG API_URL
ENV API_URL=${API_URL:?}

WORKDIR /app/web

COPY web ./
COPY schema /app/schema

RUN corepack enable
RUN corepack prepare pnpm@latest --activate
RUN pnpm install --frozen-lockfile
RUN pnpm build


FROM ruby:${RUBY_VERSION:?}-slim as base

WORKDIR /app/noodles_gff-rb

COPY noodles_gff-rb/ .

# Rails app lives here
WORKDIR /app/api

ARG APP_GID
ARG APP_UID

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    TZ=Japan


# Throw-away build stage to reduce size of final image
FROM base as build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libvips pkg-config

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

# Install packages needed for deployment
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libvips postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app/api /app/api
COPY --from=build /app/noodles_gff-rb /app/noodles_gff-rb
COPY --from=web /app/web/dist /app/api/public/web

COPY schema /app/schema

# Run and own only the runtime files as a non-root user for security
RUN mkdir /.local
RUN chown -R ${APP_UID}:${APP_GID} db log tmp /.local
USER ${APP_UID}:${APP_GID}

RUN bundle exec submission-excel2xml download_xsd

# Entrypoint prepares the database.
ENTRYPOINT ["/app/api/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/rails", "server"]
