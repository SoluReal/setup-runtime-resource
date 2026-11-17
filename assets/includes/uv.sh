#!/bin/bash

export PATH="$RUNTIME_DIR/uv/bin:$PATH"
# Interpreters a task installs from .python-version land next to the baked one, which the task user owns.
export UV_PYTHON_INSTALL_DIR="$RUNTIME_DIR/uv/python"
export UV_PYTHON_BIN_DIR="$RUNTIME_DIR/uv/bin"

if [[ "$ENABLE_CACHE" = "true" ]]; then
  export UV_CACHE_DIR="$CACHE_DIRECTORY/uv"
  # The cache volume and the venv are on different filesystems, so uv can't hardlink and would warn each install.
  export UV_LINK_MODE=copy
  register_cache_dir uv "$UV_CACHE_DIR"
  # uv keeps interpreter archives outside UV_CACHE_DIR unless pointed at one, so every run re-downloaded them.
  export UV_PYTHON_CACHE_DIR="$UV_CACHE_DIR/python"
  register_cache_dir uv/python "$UV_PYTHON_CACHE_DIR"
fi
