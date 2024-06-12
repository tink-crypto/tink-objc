#!/bin/bash
# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

# A script to postprocess the Tink XCFramework bundle.
#
# This script is meant to be invoked by the Bazel //Tink:Tink_static_xcframework
# apple_genrule target. It is not meant to be invoked directly.
#
# The primary purpose is to hide all non-Objective-C symbols from each object
# file in the bundle. Since Tink Obj-C wraps Tink C++ which includes BoringSSL,
# there's high likelihood for symbol conflicts when it's included in projects
# that link against OpenSSL. Symbol hiding avoids this issue.
#
# The ZIP file specified by the INPUT environment variable is extracted into a
# temporary directory. The BUNDLE_NAME environment variable is used to help
# navigate the directory tree.  The ZIP file contents are post processed using
# XCode tooling. The results are placed into a ZIP archive in the file specified
# by the OUTPUT environment variable.

set -x
set -e
set -u

# The following environment variables must be set.

# The ZIP file which is initially read in and processed.
if [[ -z "${INPUT}" ]]; then
  echo "The INPUT environment variable must be set."
  exit 4
fi

# The resultant ZIP file which is produced.
if [[ -z "${OUTPUT}" ]]; then
  echo "The OUTPUT environment variable must be set."
  exit 4
fi

# An identifier used to help traverse the directory tree within the ZIP file.
if [[ -z "${BUNDLE_NAME}" ]]; then
  echo "The BUNDLE_NAME environment variable must be set."
  exit 4
fi

# An argument fed to XCode tooling.
if [[ -z "${MINIMUM_IOS_VERSION}" ]]; then
  echo "The MINIMUM_IOS_VERSION environment variable must be set."
  exit 4
fi

# Create working directory.
readonly WORK_DIR="$(mktemp -d -t \
  tink_postprocess_xcframework-"$(date "+%Y%m%dT%H%M%S")")"
# Clean up on exit.
trap "rm -rf ${WORK_DIR}" EXIT

process_object_file() {
  local -r obj_file="$1"

  local -r PLATFORM="$(dirname "${obj_file}" | awk -F/ '{print $(NF-1)}')"
  cp "${obj_file}" "${WORK_DIR}/Tink.${PLATFORM}"

  # Get list of architectures.
  local archs=()
  IFS=' ' read -r -a archs < <( \
    xcrun lipo -info "${obj_file}" \
    | sed -En -e \
        's/(Non-|Architectures in the )fat file: .+( is architecture| are): (.*)$/\3/p' \
  )

  local multiple_arches=false
  if [[ "${#archs[@]}" -gt 1 ]]; then
    multiple_arches=true
  fi
  readonly multiple_arches

  local merge_cmd=( xcrun lipo )

  # Postprocess each architecture.
  for arch in "${archs[@]}"; do
    process_architecture
  done

  # Repackage processed object files.
  merge_cmd+=( -create -output "${obj_file}" )
  "${merge_cmd[@]}"
}

# Child function of process_object_file. Assumes presence of the following
# variables:
#  * objc_file
#  * arch
#  * multiple_arches
#  * merge_cmd
process_architecture() {
  # Create a subdirectory for the architeture in the working directory.
  local -r ARCH_DIR="${WORK_DIR}/${PLATFORM}.${arch}"
  mkdir "${ARCH_DIR}"

  # Extract the architecture specific object file.
  local -r ARCH_FILE="${ARCH_DIR}/${arch}"
  if [[ "${multiple_arches}" == "true" ]]; then
    xcrun lipo "${obj_file}" -thin "${arch}" -output "${ARCH_FILE}"
  else
    # Or copy it if it's already a single architecture file.
    cp "${obj_file}" "${ARCH_FILE}"
  fi

  # Extract list of Obj-C classes.
  local -r SYMBOL_QUERY="$(cat << 'EOF'
/ (D|S) _OBJC_CLASS_/     { print $3 }
/ (D|S) _OBJC_METACLASS_/ { print $3 }
/ (D|S) _TINKVersion/     { print $3 }
EOF
)"
  local -r EXPORTED_SYMBOLS_FILE="${ARCH_DIR}/exported_symbols"
  xcrun nm -g "${ARCH_FILE}" \
    | awk "${SYMBOL_QUERY}" \
    | sort -u \
    > "${EXPORTED_SYMBOLS_FILE}"

  # Hide all other symbols.
  local ld_args=()

  # Check whether bitcode is present in all sections of the object file.
  # TODO: b/335778128 - Verify if this workaround is still necessary.
  local -r BITCODE_CHECK="$(cat << 'EOF'
/^Sections:/        { sects += 1 }
/ __bitcode|__asm / { bcs += 1 }
END { if ( sects != bcs ) exit(1) }
EOF
)"
  if objdump --macho --section-headers "${ARCH_FILE}" \
      | awk "${BITCODE_CHECK}"; then
    ld_args+=( -bitcode_bundle )
  fi

  if [[ "${PLATFORM}" =~ .*simulator ]]; then
    ld_args+=( -ios_simulator_version_min )
  else
    ld_args+=( -ios_version_min )
  fi
  ld_args+=( "${MINIMUM_IOS_VERSION}" )
  readonly ld_args

  xcrun ld -r "${ld_args[@]}" \
    -force_load "${ARCH_FILE}" \
    -exported_symbols_list "${EXPORTED_SYMBOLS_FILE}" \
    -arch "${arch}" \
    -o "${ARCH_FILE}_processed.o"

  # Capture output.
  merge_cmd+=( -arch "${arch}" "${ARCH_FILE}_processed.o" )
}

main() {
  # Extract bundle.
  readonly XCFRAMEWORK_DIR="${WORK_DIR}/xcframework"
  unzip -qq "${INPUT}" -d "${XCFRAMEWORK_DIR}"

  # Find object files within the bundle.
  declare -a OBJ_FILES
  while IFS=() read -r -d $'\0' obj_file; do
    OBJ_FILES+=("${obj_file}")
  done < <(find "${XCFRAMEWORK_DIR}" -name "${BUNDLE_NAME}" -print0)
  readonly OBJ_FILES

  # Postprocess each object file.
  for obj_file in "${OBJ_FILES[@]}"; do
    process_object_file "${obj_file}"
  done

  # Repackage bundle.
  (
    cd "${XCFRAMEWORK_DIR}"
    # Zero timestamps to produce determnistic outputs.
    # The ZIP file foramt uses 2-byte DOS time format with a 1980 epoch.
    TZ=UTC find . -exec touch -h -t 198001010000 {} \+
    zip --compression-method store --symlinks --recurse-paths --quiet \
      "${OLDPWD}/${OUTPUT}" .
  )
}

main "$@"
