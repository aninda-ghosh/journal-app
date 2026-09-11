#!/bin/bash
# Kept so double-clicking the familiar file still works.
# Everything now lives in make.command, which can also run the checks.
cd "$(dirname "$0")" || exit 1
exec ./make.command build
