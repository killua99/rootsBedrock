#!/bin/sh

set -e

if [ ! -f composer.lock ]; then
  composer install
fi

exec "$@"
