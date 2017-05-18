#!/bin/sh

RUBY=${RUBY:-ruby}

while true
do
  git pull
  ${RUBY} ./br.rb build_report "$@"
done
