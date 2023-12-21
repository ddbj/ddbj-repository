#!/bin/sh

deno task gen_db

for arch in x86_64-unknown-linux-gnu x86_64-pc-windows-msvc x86_64-apple-darwin aarch64-apple-darwin; do
  mkdir -p dist/$arch

  deno compile --allow-read --allow-write --allow-env --allow-net --allow-run --allow-ffi --unstable --config=deno.json --no-check --target=$arch --output=dist/$arch/ddbj-repository run.ts

  zip -j -r dist/$arch.zip dist/$arch
done
