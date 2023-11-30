workspace(name = "tink_objc")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# Commit form Nov 22, 2023. This commit makes the @tink_cc//tink/config:global_registry target
# public, which is needed by several targets in this repo.
# TODO(ise-crypto): Replace this with a stable release that includes this change.
http_archive(
    name = "tink_cc",
    urls = ["https://github.com/tink-crypto/tink-cc/archive/73798d15c7db4f37570be562f72dc7cbfc3cc589.zip"],
    strip_prefix = "tink-cc-73798d15c7db4f37570be562f72dc7cbfc3cc589",
    sha256 = "a18ae0b19ebbc8e76e81c7db8d9866197013d2b04d68ee6ca4ac3a3c6f3b4dfd",
)

load("@tink_cc//:tink_cc_deps.bzl", "tink_cc_deps")

tink_cc_deps()

load("@tink_cc//:tink_cc_deps_init.bzl", "tink_cc_deps_init")

tink_cc_deps_init()

load("@tink_objc//:tink_objc_deps.bzl", "tink_objc_deps")

tink_objc_deps()
