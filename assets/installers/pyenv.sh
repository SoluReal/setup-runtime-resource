#!/bin/bash

function pyenv_get_dependencies() {
  if [[ "$pyenv_enabled" = "true" ]]; then
    # pyenv suggested build dependencies
    echo "lz4 ca-certificates build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev curl git libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev"
  else
    echo ""
  fi
}
