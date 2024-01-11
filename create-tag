#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

current=$(git tag --list 'v*' | tail --lines=1 | tr --delete v)
tag="v$((current + 1))"

git tag --annotate --message $tag $tag
git push --atomic origin HEAD $tag

echo
echo "=> https://github.com/ddbj/ddbj-repository/releases/tag/$tag"
