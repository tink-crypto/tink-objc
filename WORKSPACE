workspace(name = "tink_objc")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "tink_cc",
    urls = ["https://github.com/tink-crypto/tink-cc/archive/main.zip"],
    strip_prefix = "tink-cc-main",
)

load("@tink_cc//:tink_cc_deps.bzl", "tink_cc_deps")

tink_cc_deps()

load("@tink_cc//:tink_cc_deps_init.bzl", "tink_cc_deps_init")

tink_cc_deps_init()

load("@tink_objc//:tink_objc_deps.bzl", "tink_objc_deps")

tink_objc_deps()

load("@tink_objc//:tink_objc_deps_init.bzl", "tink_objc_deps_init")

tink_objc_deps_init()
