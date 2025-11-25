#!/usr/bin/env bash
set -euo pipefail

# Base directory where Rust projects will be cloned. Override via RUST_PROJECTS_DIR.
: "${RUST_PROJECTS_DIR:=${HOME}/.local/src}"

ensure_cargo_bin_path() {
  # Make cargo available for the current session if it is already installed.
  if [ -d "${HOME}/.cargo/bin" ] && ! command -v cargo >/dev/null 2>&1; then
    export PATH="${HOME}/.cargo/bin:${PATH}"
  fi
}

install_rust_project() {
  # Args:
  #   $1: repo path (e.g., asuto15/kintai or github.com/asuto15/kintai)
  #   $2: binary name to check/install (defaults to repo name)
  local repo_input="$1"
  local binary_name="${2:-$(basename "${repo_input}")}"

  ensure_cargo_bin_path

  if command -v "${binary_name}" >/dev/null 2>&1; then
    echo "${binary_name} already installed; skipping."
    return
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    echo "warn: cargo is not available; skipping ${binary_name}."
    return
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "warn: git is not available; skipping ${binary_name}."
    return
  fi

  # Normalize repo path and derive clone target.
  local repo_path="${repo_input#https://github.com/}"
  repo_path="${repo_path#http://github.com/}"
  repo_path="${repo_path#github.com/}"
  repo_path="${repo_path%.git}"
  repo_path="${repo_path#/}" # guard against accidental leading slash

  local repo_url="https://github.com/${repo_path}.git"
  local repo_dir="${RUST_PROJECTS_DIR}/github.com/${repo_path}"

  mkdir -p "$(dirname "${repo_dir}")"

  if [ -d "${repo_dir}/.git" ]; then
    echo "Updating ${repo_path}..."
    if ! git -C "${repo_dir}" pull --ff-only --quiet; then
      git -C "${repo_dir}" pull --ff-only || true
    fi
  else
    echo "Cloning ${repo_url}..."
    git clone --depth 1 "${repo_url}" "${repo_dir}"
  fi

  echo "cargo install --path ${repo_dir}"
  if ! cargo install --path "${repo_dir}" --locked; then
    cargo install --path "${repo_dir}" || true
  fi
}

install_rust_projects() {
  install_rust_project "asuto15/kintai" "kintai"
  install_rust_project "asuto15/ogp-checker" "ogp-checker"
  install_rust_project "asuto15/cbcopy" "cbcopy"
}
