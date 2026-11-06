#!/usr/bin/env bash
# Все tests/*_spec.lua по очереди (`nvim -l`); останов на первом падении,
# код выхода — итог. Работает из любого каталога.
set -u
cd "$(dirname "$0")/.." || exit 1
for spec in tests/*_spec.lua; do
  echo "== $spec"
  if ! nvim --headless --clean -u NONE -l "$spec"; then
    echo "FAILED: $spec"
    exit 1
  fi
done
echo "ALL OK"
