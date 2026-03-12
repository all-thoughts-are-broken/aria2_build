#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <linux|macos> <package-version> <work-dir> <output-dir> [aria2-ref]" >&2
}

if [[ $# -lt 4 || $# -gt 5 ]]; then
  usage
  exit 1
fi

platform="$1"
package_version="$2"
work_dir="$3"
output_dir="$4"
aria2_ref="${5:-master}"

case "$platform" in
  linux|macos)
    ;;
  *)
    usage
    exit 1
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

aria2_repo_url="${ARIA2_REPO_URL:-https://github.com/aria2/aria2.git}"
aria2_local_source="${ARIA2_SOURCE_DIR:-${repo_root}/aria2}"
source_origin="$aria2_repo_url"
is_local_source=0
if [[ -d "${aria2_local_source}/.git" ]]; then
  source_origin="$aria2_local_source"
  is_local_source=1
fi

source_dir="${work_dir}/aria2-source"
build_dir="${work_dir}/build-${platform}"
install_dir="${work_dir}/install-${platform}"
package_dir="${output_dir}/package"

mkdir -p "$work_dir" "$output_dir"
rm -rf "$source_dir" "$build_dir" "$install_dir" "$package_dir"

echo "Cloning aria2 from ${source_origin} (${aria2_ref})"
if [[ "$is_local_source" -eq 1 ]]; then
  git clone --branch "$aria2_ref" "$source_origin" "$source_dir"
else
  git clone --depth 1 --branch "$aria2_ref" "$source_origin" "$source_dir"
fi

if [[ "$platform" == "macos" && -z "${LIBTOOLIZE:-}" ]] && command -v glibtoolize >/dev/null 2>&1; then
  export LIBTOOLIZE=glibtoolize
fi

pushd "$source_dir" >/dev/null
autoreconf -fi
popd >/dev/null

mkdir -p "$build_dir"
pushd "$build_dir" >/dev/null

common_args=(
  "--prefix=${install_dir}"
  "--enable-libaria2"
  "--enable-static"
  "--disable-shared"
  "--disable-bittorrent"
  "--disable-metalink"
  "--disable-websocket"
  "--without-libxml2"
  "--without-libexpat"
  "--without-libssh2"
  "--without-sqlite3"
  "--without-libcares"
  "--without-libnettle"
  "--without-libgmp"
  "--without-libgcrypt"
  "--disable-epoll"
)

extra_args=()
case "$platform" in
  linux)
    extra_args=(
      "--with-openssl"
      "--without-gnutls"
      "--without-appletls"
      "--without-wintls"
    )
    ;;
  macos)
    extra_args=(
      "--without-openssl"
      "--without-gnutls"
      "--without-wintls"
    )
    ;;
esac

"${source_dir}/configure" "${common_args[@]}" "${extra_args[@]}"

build_jobs="$(
  getconf _NPROCESSORS_ONLN 2>/dev/null ||
  sysctl -n hw.logicalcpu 2>/dev/null ||
  echo 4
)"

make -j"${build_jobs}"
make install
popd >/dev/null

mkdir -p "${package_dir}/include/aria2" "${package_dir}/lib" "${package_dir}/cmake"

cp "${install_dir}/include/aria2/aria2.h" "${package_dir}/include/aria2/aria2.h"
cp "${install_dir}/lib/libaria2.a" "${package_dir}/lib/libaria2.a"
cp "${source_dir}/COPYING" "${package_dir}/LICENSE.aria2.txt"
if [[ -f "${source_dir}/LICENSE.OpenSSL" ]]; then
  cp "${source_dir}/LICENSE.OpenSSL" "${package_dir}/LICENSE.OpenSSL.txt"
fi

cat > "${package_dir}/cmake/Aria2ConfigVersion.cmake" <<EOF
set(PACKAGE_VERSION "${package_version}")

if(PACKAGE_FIND_VERSION VERSION_GREATER PACKAGE_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
else()
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
  if(PACKAGE_FIND_VERSION VERSION_EQUAL PACKAGE_VERSION)
    set(PACKAGE_VERSION_EXACT TRUE)
  endif()
endif()
EOF

if [[ "$platform" == "linux" ]]; then
  cat > "${package_dir}/cmake/Aria2Config.cmake" <<'EOF'
get_filename_component(_ARIA2_PREFIX "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

include(CMakeFindDependencyMacro)
find_dependency(ZLIB)
find_dependency(OpenSSL)

if(NOT TARGET Aria2::aria2)
  add_library(Aria2::aria2 STATIC IMPORTED)
  set_target_properties(Aria2::aria2 PROPERTIES
    IMPORTED_LOCATION "${_ARIA2_PREFIX}/lib/libaria2.a"
    INTERFACE_INCLUDE_DIRECTORIES "${_ARIA2_PREFIX}/include"
    INTERFACE_LINK_LIBRARIES "ZLIB::ZLIB;OpenSSL::SSL;OpenSSL::Crypto"
  )
endif()

unset(_ARIA2_PREFIX)
EOF
else
  cat > "${package_dir}/cmake/Aria2Config.cmake" <<'EOF'
get_filename_component(_ARIA2_PREFIX "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

include(CMakeFindDependencyMacro)
find_dependency(ZLIB)

find_library(_ARIA2_FRAMEWORK_COREFOUNDATION CoreFoundation REQUIRED)
find_library(_ARIA2_FRAMEWORK_SECURITY Security REQUIRED)

if(NOT TARGET Aria2::aria2)
  add_library(Aria2::aria2 STATIC IMPORTED)
  set_target_properties(Aria2::aria2 PROPERTIES
    IMPORTED_LOCATION "${_ARIA2_PREFIX}/lib/libaria2.a"
    INTERFACE_INCLUDE_DIRECTORIES "${_ARIA2_PREFIX}/include"
    INTERFACE_LINK_LIBRARIES
      "ZLIB::ZLIB;${_ARIA2_FRAMEWORK_COREFOUNDATION};${_ARIA2_FRAMEWORK_SECURITY}"
  )
endif()

unset(_ARIA2_FRAMEWORK_COREFOUNDATION)
unset(_ARIA2_FRAMEWORK_SECURITY)
unset(_ARIA2_PREFIX)
EOF
fi

echo "Package created at ${package_dir}"
