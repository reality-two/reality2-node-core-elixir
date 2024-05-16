#!/bin/sh
echo -ne '\033c\033]0;SentantVisualiser\a'
base_path="$(dirname "$(realpath "$0")")"
"$base_path/reality2.x86_64" "$@"
