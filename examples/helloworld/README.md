# Tink Obj-C Hello World

This is an example iOS application that can encrypt and decrypt text using
the [AEAD (Authenticated Encryption with Associated
Data)](https://developers.google.com/tink/aead) primitive.

It demonstrates the basic steps of using Tink:

*   generating key material
*   obtaining a primitive
*   using the primitive to do crypto

## Build and run

### CocoaPods

```shell
git clone https://github.com/tink-crypto/tink-objc
cd examples/helloworld
pod install
open TinkExampleApp.xcworkspace
```

### Bazel

```shell
git clone https://github.com/tink-crypto/tink-objc
cd examples/helloworld
bazelisk run //helloworld/bazel:xcodeproj
open bazel/TinkExampleApp.xcodeproj
```
