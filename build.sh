#!/bin/bash

set -e

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${CYAN}$1${NC}"; }
log_success() { echo -e "${GREEN}✓ $1${NC}"; }
log_error() { echo -e "${RED}✗ Error: $1${NC}"; }
log_warning() { echo -e "${YELLOW}$1${NC}"; }
log_step() { echo -e "${PURPLE}$1${NC}"; }
log_build() { echo -e "${BLUE}$1${NC}"; }

# Main function to run the build script
main() {
    parse_args "$@"
    set_defaults
    git_version="v4.1.8"  # This should be dynamically fetched in a real scenario
    if [[ "$LITE_FLAG" == "true" ]]; then
        archive_name="openlist-frontend-dist-lite-v4.1.8"
        version_tag="v4.1.8"
    else
        archive_name="openlist-frontend-dist-v4.1.8"
        version_tag="v4.1.8"
    fi
    build_project
    create_version_file
    handle_compression
    log_success "Build completed."
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dev) BUILD_TYPE="dev"; shift ;;
            --release) BUILD_TYPE="release"; shift ;;
            --compress) COMPRESS_FLAG="true"; shift ;;
            --no-compress) COMPRESS_FLAG="false"; shift ;;
            --enforce-tag) ENFORCE_TAG="true"; shift ;;
            --skip-i18n) SKIP_I18N="true"; shift ;;
            --lite) LITE_FLAG="true"; shift ;;
            -h|--help) display_help; exit 0 ;;
            *) log_error "Unknown option: $1"; display_help; exit 1 ;;
        esac
    done
}

# Display help message
display_help() {
    echo "Usage: $0 [--dev|--release] [--compress|--no-compress] [--enforce-tag] [--skip-i18n] [--lite]"
    echo ""
    echo "Options (will overwrite environment setting):"
    echo "  --dev         Build development version"
    echo "  --release     Build release version (will check if git tag match package.json version)"
    echo "  --compress    Create compressed archive"
    echo "  --no-compress Skip compression"
    echo "  --enforce-tag Force git tag requirement for both dev and release builds"
    echo "  --skip-i18n   Skip i18n build step"
    echo "  --lite        Build lite version"
    echo ""
    echo "Environment variables:"
    echo "  OPENLIST_FRONTEND_BUILD_MODE=dev|release (default: dev)"
    echo "  OPENLIST_FRONTEND_BUILD_COMPRESS=true|false (default: false)"
    echo "  OPENLIST_FRONTEND_BUILD_ENFORCE_TAG=true|false (default: false)"
    echo "  OPENLIST_FRONTEND_BUILD_SKIP_I18N=true|false (default: false)"
}

# Set default values from environment variables
set_defaults() {
    BUILD_TYPE=${BUILD_TYPE:-${OPENLIST_FRONTEND_BUILD_MODE:-dev}}
    COMPRESS_FLAG=${COMPRESS_FLAG:-${OPENLIST_FRONTEND_BUILD_COMPRESS:-false}}
    ENFORCE_TAG=${ENFORCE_TAG:-${OPENLIST_FRONTEND_BUILD_ENFORCE_TAG:-false}}
    SKIP_I18N=${SKIP_I18N:-${OPENLIST_FRONTEND_BUILD_SKIP_I18N:-false}}
    LITE_FLAG=${LITE_FLAG:-false}
}

# Build the project
build_project() {
    log_step "==== Installing dependencies ===="
    pnpm install

    log_step "==== Building i18n ===="
    if [[ "$SKIP_I18N" == "false" ]]; then
        pnpm i18n:release
    else
        fetch_i18n_from_release
    fi

    log_step "==== Building project ===="
    if [[ "$LITE_FLAG" == "true" ]]; then
        pnpm build:lite
    else
        pnpm build
    fi
}

# Fetch i18n files from release if skip-i18n flag is set
fetch_i18n_from_release() {
    log_warning "Skipping i18n build step, try to fetch from GitHub release"
    release_response=$(curl -s "https://api.github.com/repos/OpenListTeam/OpenList-Frontend/releases/tags/$git_version")
    if echo -n "$release_response" | grep -q "Not Found"; then
        log_warning "Failed to fetch release info. Skipping i18n fetch."
    else
        extract_i18n_tarball "$release_response"
    fi
}

# Extract i18n tarball
extract_i18n_tarball() {
    i18n_file_url=$(echo "$1" | grep -oP '"browser_download_url":\s*"\K[^"]*' | grep "i18n.tar.gz") || true
    if [[ -z "$i18n_file_url" ]]; then
        log_warning "i18n.tar.gz not found in release assets. Skipping i18n fetch."
    else
        log_info "Downloading i18n.tar.gz from GitHub..."
        if curl -L -o "i18n.tar.gz" "$i18n_file_url"; then
            if tar -xzvf i18n.tar.gz -C src/lang; then
                log_info "i18n files extracted to src/lang/"
            else
                log_warning "Failed to extract i18n.tar.gz"
            fi
        else
            log_warning "Failed to download i18n.tar.gz"
        fi
    fi
}

# Create VERSION file in the dist directory
create_version_file() {
    log_step "Writing version $version_tag to dist/VERSION..."
    echo -n "$version_tag" > dist/VERSION
    log_success "Version file created: dist/VERSION"
}

# Handle compression if requested
handle_compression() {
    if [[ "$COMPRESS_FLAG" == "true" ]]; then
        log_step "Creating compressed archive..."
        tar -czvf "${archive_name}.tar.gz" -C dist .
        tar -czvf "i18n.tar.gz" --exclude=en -C src/lang .
        mv "${archive_name}.tar.gz" dist/
        mv "i18n.tar.gz" dist/
        log_success "Compressed archive created: dist/${archive_name}.tar.gz dist/i18n.tar.gz"
    fi
}

# Run the script
main "$@"
