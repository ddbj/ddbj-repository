#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

current=$(git tag --list 'v*' | tr --delete v | sort --numeric-sort | tail --lines=1)
tag="v$((current + 1))"

git tag --annotate --message $tag $tag
git push --atomic origin HEAD $tag

echo
echo "=> https://github.com/ddbj/ddbj-repository/releases/tag/$tag"
