/**
 * Copyright 2017 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 **************************************************************************
 */

#import "Tink/TINKKeysetHandle.h"
#import "Tink/core/TINKKeysetHandle_Internal.h"

#import <Security/Security.h>
#import <XCTest/XCTest.h>

#include <memory>
#include <string>
#include <utility>

#import "Tink/TINKAead.h"
#import "Tink/TINKAeadKeyTemplate.h"
#import "Tink/TINKAllConfig.h"
#import "Tink/TINKBinaryKeysetReader.h"
#import "Tink/TINKConfig.h"
#import "Tink/TINKHybridKeyTemplate.h"
#import "Tink/TINKSignatureKeyTemplate.h"
#import "Tink/aead/TINKAeadInternal.h"
#import "Tink/util/TINKStrings.h"

#include "absl/status/status.h"
#include "tink/binary_keyset_reader.h"
#include "tink/insecure_secret_key_access.h"
#include "tink/proto_keyset_format.h"
#include "tink/secret_data.h"
#include "tink/util/secret_data.h"
#include "tink/util/status.h"
#include "tink/util/test_util.h"
#include "Tink/proto_redirect/tink_cc_pb_redirect.h"

using ::crypto::tink::InsecureSecretKeyAccess;
using ::crypto::tink::SerializeKeysetToProtoKeysetFormat;
using ::crypto::tink::test::AddRawKey;
using ::crypto::tink::test::AddTinkKey;
using ::crypto::tink::SecretData;
using ::crypto::tink::util::SecretDataAsStringView;
using ::crypto::tink::util::StatusOr;
using ::google::crypto::tink::EncryptedKeyset;
using ::google::crypto::tink::KeyData;
using ::google::crypto::tink::Keyset;
using ::google::crypto::tink::KeyStatusType;

// Variables used to hold the serialized keyset data.
static NSData *gBadSerializedKeyset;
static NSData *gGoodSerializedKeyset;

// Verbatim copy of the service constant defined in TINKKeychainKeysetReader.
static NSString *const kTinkService = @"com.google.crypto.tink";

// Keyset names used in the tests below.
static NSString *const kGoodKeysetName = @"com.google.crypto.tink.goodKeyset";
static NSString *const kBadKeysetName = @"com.google.crypto.tink.badKeyset";
static NSString *const kNonExistentKeysetName = @"com.google.crypto.tink.noSuchKeyset";

static Keyset *gKeyset;

@interface TINKKeysetHandleTest : XCTestCase
@end

@implementation TINKKeysetHandleTest

+ (void)setUp {
  gKeyset = new Keyset();
  google::crypto::tink::Keyset::Key ccKey;

  crypto::tink::test::AddTinkKey("some_key_type", 42, ccKey,
                                 google::crypto::tink::KeyStatusType::ENABLED,
                                 google::crypto::tink::KeyData::SYMMETRIC, gKeyset);
  crypto::tink::test::AddRawKey("some_other_key_type", 711, ccKey,
                                google::crypto::tink::KeyStatusType::ENABLED,
                                google::crypto::tink::KeyData::SYMMETRIC, gKeyset);
  gKeyset->set_primary_key_id(42);

  std::string serializedKeyset = gKeyset->SerializeAsString();
  gGoodSerializedKeyset = TINKStringToNSData(serializedKeyset);

  NSError *error = nil;
  XCTAssertTrue(gKeyset != nil);
  XCTAssertNil(error);

  gBadSerializedKeyset = TINKStringToNSData("some weird string");

  error = nil;
  TINKAllConfig *allConfig = [[TINKAllConfig alloc] initWithError:&error];
  XCTAssertNotNil(allConfig);
  XCTAssertNil(error);

  XCTAssertTrue([TINKConfig registerConfig:allConfig error:&error]);
  XCTAssertNil(error);
}

- (void)setUp {
  // Add the two keysets in the keychain. We do this here because we can use XCTAssert to test that
  // SecItemAdd succeeds. It would be better in +setUp but XCTAssert isn't available.
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSDictionary *attr = @{
      (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
      (__bridge id)
      kSecAttrAccessible : (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      (__bridge id)kSecAttrService : kTinkService,
      (__bridge id)kSecAttrSynchronizable : (__bridge id)kCFBooleanFalse,
    };
    NSMutableDictionary *attributes = [attr mutableCopy];

    // Store the keyset.
    [attributes setObject:kGoodKeysetName forKey:(__bridge id)kSecAttrAccount];
    [attributes setObject:gGoodSerializedKeyset forKey:(__bridge id)kSecValueData];
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)attributes, nullptr);
    XCTAssertTrue(status == errSecSuccess || status == errSecDuplicateItem);

    // Store the bad keyset.
    [attributes setObject:kBadKeysetName forKey:(__bridge id)kSecAttrAccount];
    [attributes setObject:gBadSerializedKeyset forKey:(__bridge id)kSecValueData];
    status = SecItemAdd((__bridge CFDictionaryRef)attributes, nullptr);
    XCTAssertTrue(status == errSecSuccess || status == errSecDuplicateItem);
  });
}

- (void)testGoodEncryptedKeyset_Binary {
  auto ccAead =
      std::unique_ptr<crypto::tink::Aead>(new crypto::tink::test::DummyAead("dummy aead 42"));
  TINKAeadInternal *aead = [[TINKAeadInternal alloc] initWithCCAead:std::move(ccAead)];

  std::string serializedKeyset = gKeyset->SerializeAsString();
  NSData *serializedKeysetData = [[NSData alloc] initWithBytes:serializedKeyset.data()
                                                        length:serializedKeyset.size()];
  NSData *keysetCiphertext = [aead encrypt:serializedKeysetData
                        withAdditionalData:[NSData data]
                                     error:nil];

  XCTAssertNotNil(keysetCiphertext);

  EncryptedKeyset encryptedKeyset;
  encryptedKeyset.set_encrypted_keyset(NSDataToTINKString(keysetCiphertext));

  TINKBinaryKeysetReader *reader = [[TINKBinaryKeysetReader alloc]
      initWithSerializedKeyset:TINKStringToNSData(encryptedKeyset.SerializeAsString())
                         error:nil];

  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initWithKeysetReader:reader andKey:aead error:nil];
  XCTAssertNotNil(handle);
  StatusOr<SecretData> serialized =
      SerializeKeysetToProtoKeysetFormat(*handle.ccKeysetHandle, InsecureSecretKeyAccess::Get());
  XCTAssertTrue(serialized.ok());
  XCTAssertEqualObjects(serializedKeysetData,
                        TINKStringViewToNSData(SecretDataAsStringView(*serialized)));
}

- (void)testWrongAead_Binary {
  auto ccAead =
      std::unique_ptr<crypto::tink::Aead>(new crypto::tink::test::DummyAead("dummy aead 42"));
  TINKAeadInternal *aead = [[TINKAeadInternal alloc] initWithCCAead:std::move(ccAead)];

  std::string serializedKeyset = gKeyset->SerializeAsString();
  NSData *serializedKeysetData = [[NSData alloc] initWithBytes:serializedKeyset.data()
                                                        length:serializedKeyset.size()];

  NSData *keysetCiphertext = [aead encrypt:serializedKeysetData
                        withAdditionalData:[NSData data]
                                     error:nil];

  EncryptedKeyset encryptedKeyset;
  encryptedKeyset.set_encrypted_keyset(NSDataToTINKString(keysetCiphertext));

  TINKBinaryKeysetReader *reader = [[TINKBinaryKeysetReader alloc]
      initWithSerializedKeyset:TINKStringToNSData(encryptedKeyset.SerializeAsString())
                         error:nil];

  auto ccWrongAead =
      std::unique_ptr<crypto::tink::Aead>(new crypto::tink::test::DummyAead("wrong aead"));
  TINKAeadInternal *wrongAead = [[TINKAeadInternal alloc] initWithCCAead:std::move(ccWrongAead)];

  NSError *error = nil;
  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initWithKeysetReader:reader andKey:wrongAead error:&error];
  XCTAssertNil(handle);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kInvalidArgument);
}

- (void)testNoKeysetInCiphertext_Binary {
  auto ccAead =
      std::unique_ptr<crypto::tink::Aead>(new crypto::tink::test::DummyAead("dummy aead 42"));
  TINKAeadInternal *aead = [[TINKAeadInternal alloc] initWithCCAead:std::move(ccAead)];
  NSData *keysetCiphertext =
      [aead encrypt:[@"not a serialized keyset" dataUsingEncoding:NSUTF8StringEncoding]
          withAdditionalData:[NSData data]
                       error:nil];

  TINKBinaryKeysetReader *reader =
      [[TINKBinaryKeysetReader alloc] initWithSerializedKeyset:keysetCiphertext error:nil];

  NSError *error = nil;
  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initWithKeysetReader:reader andKey:aead error:&error];
  XCTAssertNil(handle);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kInvalidArgument);
}

- (void)testWrongCiphertext_Binary {
  auto ccAead =
      std::unique_ptr<crypto::tink::Aead>(new crypto::tink::test::DummyAead("dummy aead 42"));
  TINKAeadInternal *aead = [[TINKAeadInternal alloc] initWithCCAead:std::move(ccAead)];
  NSData *keysetCiphertext = [@"totally wrong ciphertext" dataUsingEncoding:NSUTF8StringEncoding];

  EncryptedKeyset encryptedKeyset;
  encryptedKeyset.set_encrypted_keyset(NSDataToTINKString(keysetCiphertext));

  TINKBinaryKeysetReader *reader = [[TINKBinaryKeysetReader alloc]
      initWithSerializedKeyset:TINKStringToNSData(encryptedKeyset.SerializeAsString())
                         error:nil];
  NSError *error = nil;
  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initWithKeysetReader:reader andKey:aead error:&error];
  XCTAssertNil(handle);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kInvalidArgument);
}

- (void)testValidKeyTemplate {
  NSError *error = nil;
  TINKHybridKeyTemplate *keyTemplate =
      [[TINKHybridKeyTemplate alloc] initWithKeyTemplate:TINKEciesP256HkdfHmacSha256Aes128Gcm
                                                   error:&error];
  XCTAssertNotNil(keyTemplate);
  XCTAssertNil(error);

  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initWithKeyTemplate:keyTemplate error:&error];
  XCTAssertNotNil(handle);
  XCTAssertNil(error);
}

- (void)testReuseKeysetReader {
  auto ccAead =
      std::unique_ptr<crypto::tink::Aead>(new crypto::tink::test::DummyAead("dummy aead 42"));
  TINKAeadInternal *aead = [[TINKAeadInternal alloc] initWithCCAead:std::move(ccAead)];

  std::string serializedKeyset = gKeyset->SerializeAsString();
  NSData *serializedKeysetData = [[NSData alloc] initWithBytes:serializedKeyset.data()
                                                        length:serializedKeyset.size()];
  NSData *keysetCiphertext = [aead encrypt:serializedKeysetData
                        withAdditionalData:[NSData data]
                                     error:nil];

  XCTAssertNotNil(keysetCiphertext);

  EncryptedKeyset encryptedKeyset;
  encryptedKeyset.set_encrypted_keyset(NSDataToTINKString(keysetCiphertext));

  TINKBinaryKeysetReader *reader = [[TINKBinaryKeysetReader alloc]
      initWithSerializedKeyset:TINKStringToNSData(encryptedKeyset.SerializeAsString())
                         error:nil];

  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initWithKeysetReader:reader andKey:aead error:nil];
  XCTAssertNotNil(handle);

  NSError *error = nil;
  XCTAssertNil([[TINKKeysetHandle alloc] initWithKeysetReader:reader andKey:aead error:&error]);
  XCTAssertNotNil(error);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kResourceExhausted);
  XCTAssertTrue(
      [error.localizedFailureReason containsString:@"A KeysetReader can be used only once."]);
}

- (void)testGoodKeysetFromKeychain {
  NSError *error = nil;
  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initFromKeychainWithName:kGoodKeysetName error:&error];
  XCTAssertNotNil(handle);
  XCTAssertNil(error);

  // Verify the contents of the keyset.
  StatusOr<SecretData> serialized =
      SerializeKeysetToProtoKeysetFormat(*handle.ccKeysetHandle, InsecureSecretKeyAccess::Get());
  XCTAssertTrue(serialized.ok());

  XCTAssertEqualObjects(gGoodSerializedKeyset,
                        TINKStringViewToNSData(SecretDataAsStringView(*serialized)));
}

- (void)testBadKeysetFromKeychain {
  NSError *error = nil;
  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initFromKeychainWithName:kBadKeysetName error:&error];
  XCTAssertNil(handle);
  XCTAssertNotNil(error);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kInvalidArgument);
  XCTAssertTrue([error.localizedFailureReason
      containsString:@"Could not parse the input stream as a Keyset-proto."]);
}

- (void)testUnknownKeysetFromKeychain {
  NSError *error = nil;
  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initFromKeychainWithName:kNonExistentKeysetName error:&error];
  XCTAssertNil(handle);
  XCTAssertNotNil(error);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kNotFound);
  XCTAssertTrue([error.localizedFailureReason
      containsString:@"A keyset with the given name wasn't found in the keychain."]);
}

- (void)testWriteKeysetToKeychain {
  static NSString *const kKeysetName = @"com.google.crypto.tink.randomaeadkeyset";

  NSError *error = nil;
  // Generate a new fresh keyset for Aead.
  TINKAeadKeyTemplate *tpl =
      [[TINKAeadKeyTemplate alloc] initWithKeyTemplate:TINKAes128Gcm error:&error];
  XCTAssertNotNil(tpl);
  XCTAssertNil(error);

  TINKKeysetHandle *handle1 = [[TINKKeysetHandle alloc] initWithKeyTemplate:tpl error:&error];
  XCTAssertNotNil(handle1);
  XCTAssertNil(error);

  // Delete any previous keychain items with the same name.
  NSDictionary *attr = @{
    (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
    (__bridge id)kSecAttrAccessible : (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    (__bridge id)kSecAttrService : kTinkService,
    (__bridge id)kSecAttrSynchronizable : (__bridge id)kCFBooleanFalse,
    (__bridge id)kSecAttrAccount : kKeysetName,
  };
  OSStatus deleteStatus = SecItemDelete((__bridge CFDictionaryRef)attr);
  XCTAssertTrue(deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound);

  // Store the keyset in the iOS keychain.
  XCTAssertTrue([handle1 writeToKeychainWithName:kKeysetName overwrite:NO error:&error]);
  XCTAssertNil(error);

  // Generate a new handle using the stored keyset.
  TINKKeysetHandle *handle2 =
      [[TINKKeysetHandle alloc] initFromKeychainWithName:kKeysetName error:&error];
  XCTAssertNotNil(handle2);
  XCTAssertNil(error);

  // Compare the two keysets, verify that they are identical.
  StatusOr<SecretData> serializedKeyset1 =
      SerializeKeysetToProtoKeysetFormat(*handle1.ccKeysetHandle, InsecureSecretKeyAccess::Get());
  XCTAssertTrue(serializedKeyset1.ok());

  StatusOr<SecretData> serializedKeyset2 =
      SerializeKeysetToProtoKeysetFormat(*handle2.ccKeysetHandle, InsecureSecretKeyAccess::Get());
  XCTAssertTrue(serializedKeyset2.ok());

  XCTAssertEqualObjects(TINKStringViewToNSData(SecretDataAsStringView(*serializedKeyset1)),
                        TINKStringViewToNSData(SecretDataAsStringView(*serializedKeyset2)));
}

- (void)testDeleteKeysetFromKeychain {
  static NSString *const kKeysetName = @"com.google.crypto.tink.somekeyset";

  NSError *error = nil;
  // Generate a new fresh keyset for Aead.
  TINKAeadKeyTemplate *tpl =
      [[TINKAeadKeyTemplate alloc] initWithKeyTemplate:TINKAes128Gcm error:&error];
  XCTAssertNotNil(tpl);
  XCTAssertNil(error);

  TINKKeysetHandle *handle1 = [[TINKKeysetHandle alloc] initWithKeyTemplate:tpl error:&error];
  XCTAssertNotNil(handle1);
  XCTAssertNil(error);

  // Store the keyset in the iOS keychain.
  XCTAssertTrue([handle1 writeToKeychainWithName:kKeysetName overwrite:NO error:&error]);
  XCTAssertNil(error);

  // Delete it.
  XCTAssertTrue([TINKKeysetHandle deleteFromKeychainWithName:kKeysetName error:&error]);
  XCTAssertNil(error);

  // Try again. Should succeed with ItemNotFound.
  XCTAssertTrue([TINKKeysetHandle deleteFromKeychainWithName:kKeysetName error:&error]);
  XCTAssertNil(error);
}

- (void)testPublicKeysetHandleWithHandle {
  NSError *error = nil;
  TINKSignatureKeyTemplate *tpl =
      [[TINKSignatureKeyTemplate alloc] initWithKeyTemplate:TINKEcdsaP256 error:&error];
  XCTAssertNotNil(tpl);
  XCTAssertNil(error);

  TINKKeysetHandle *handle = [[TINKKeysetHandle alloc] initWithKeyTemplate:tpl error:&error];
  XCTAssertNotNil(handle);
  XCTAssertNil(error);

  TINKKeysetHandle *publicHandle = [TINKKeysetHandle publicKeysetHandleWithHandle:handle
                                                                            error:&error];
  XCTAssertNotNil(publicHandle);
  XCTAssertNil(error);

  StatusOr<SecretData> serializedKeyset =
      SerializeKeysetToProtoKeysetFormat(*handle.ccKeysetHandle, InsecureSecretKeyAccess::Get());
  XCTAssertTrue(serializedKeyset.ok());

  StatusOr<SecretData> serializedPublicKeyset = SerializeKeysetToProtoKeysetFormat(
      *publicHandle.ccKeysetHandle, InsecureSecretKeyAccess::Get());
  XCTAssertTrue(serializedKeyset.ok());

  Keyset keyset;
  XCTAssertTrue(
      keyset.ParseFromString(std::string(SecretDataAsStringView(*serializedKeyset))));
  Keyset publicKeyset;
  XCTAssertTrue(
      publicKeyset.ParseFromString(std::string(SecretDataAsStringView(*serializedPublicKeyset))));

  XCTAssertEqual(keyset.primary_key_id(), publicKeyset.primary_key_id());
  XCTAssertEqual(keyset.key_size(), publicKeyset.key_size());
  XCTAssertEqual(keyset.key(0).status(), publicKeyset.key(0).status());
  XCTAssertEqual(keyset.key(0).key_id(), publicKeyset.key(0).key_id());
  XCTAssertEqual(keyset.key(0).output_prefix_type(), publicKeyset.key(0).output_prefix_type());
  XCTAssertEqual(google::crypto::tink::KeyData::ASYMMETRIC_PUBLIC,
                 publicKeyset.key(0).key_data().key_material_type());
}

- (void)testPublicKeysetHandleWithHandleFailedNotAsymmetric {
  NSError *error = nil;
  TINKAeadKeyTemplate *tpl = [[TINKAeadKeyTemplate alloc] initWithKeyTemplate:TINKAes128Eax
                                                                        error:&error];
  XCTAssertNotNil(tpl);
  XCTAssertNil(error);

  TINKKeysetHandle *handle = [[TINKKeysetHandle alloc] initWithKeyTemplate:tpl error:&error];
  XCTAssertNotNil(handle);
  XCTAssertNil(error);

  TINKKeysetHandle *publicHandle = [TINKKeysetHandle publicKeysetHandleWithHandle:handle
                                                                            error:&error];
  XCTAssertNil(publicHandle);
  XCTAssertNotNil(error);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kInvalidArgument);
  XCTAssertTrue([error.localizedFailureReason
      containsString:@"Key material is not of type KeyData::ASYMMETRIC_PRIVATE"]);
}

- (void)testReadNoSecret {
  auto keyset = std::make_unique<Keyset>();
  Keyset::Key key;
  AddTinkKey("some_key_type", 42, key, KeyStatusType::ENABLED, KeyData::ASYMMETRIC_PUBLIC,
             keyset.get());
  AddRawKey("some_other_key_type", 711, key, KeyStatusType::ENABLED, KeyData::REMOTE, keyset.get());
  keyset->set_primary_key_id(42);
  NSData *serializedKeyset = TINKStringToNSData(keyset->SerializeAsString());
  NSError *error = nil;
  TINKKeysetHandle *handle = [[TINKKeysetHandle alloc] initWithNoSecretKeyset:serializedKeyset
                                                                        error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(handle);
  StatusOr<SecretData> ccSerializedKeysetSecretData =
      SerializeKeysetToProtoKeysetFormat(*handle.ccKeysetHandle, InsecureSecretKeyAccess::Get());
  XCTAssertTrue(ccSerializedKeysetSecretData.ok());
  NSData *ccSerializedKeyset =
      TINKStringViewToNSData(SecretDataAsStringView(*ccSerializedKeysetSecretData));
  XCTAssertEqualObjects(ccSerializedKeyset, serializedKeyset);
}

- (void)testReadNoSecretFailForTypeUnknown {
  auto keyset = std::make_unique<Keyset>();
  Keyset::Key key;
  AddTinkKey("some_key_type", 42, key, KeyStatusType::ENABLED, KeyData::UNKNOWN_KEYMATERIAL,
             keyset.get());
  keyset->set_primary_key_id(42);
  NSData *serializedKeyset = TINKStringToNSData(keyset->SerializeAsString());
  NSError *error = nil;
  TINKKeysetHandle *handle = [[TINKKeysetHandle alloc] initWithNoSecretKeyset:serializedKeyset
                                                                        error:&error];

  XCTAssertNil(handle);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kFailedPrecondition);
  XCTAssertTrue([error.localizedFailureReason
      containsString:@"Cannot create KeysetHandle with secret key material"]);
}

- (void)testReadNoSecretFailForTypeSymmetric {
  auto keyset = std::make_unique<Keyset>();
  Keyset::Key key;
  AddTinkKey("some_key_type", 42, key, KeyStatusType::ENABLED, KeyData::SYMMETRIC, keyset.get());
  keyset->set_primary_key_id(42);
  NSData *serializedKeyset = TINKStringToNSData(keyset->SerializeAsString());
  NSError *error = nil;
  TINKKeysetHandle *handle = [[TINKKeysetHandle alloc] initWithNoSecretKeyset:serializedKeyset
                                                                        error:&error];

  XCTAssertNil(handle);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kFailedPrecondition);
  XCTAssertTrue([error.localizedFailureReason
      containsString:@"Cannot create KeysetHandle with secret key material"]);
}

- (void)testReadNoSecretFailForTypeAssymmetricPrivate {
  auto keyset = std::make_unique<Keyset>();
  Keyset::Key key;
  AddTinkKey("some_key_type", 42, key, KeyStatusType::ENABLED, KeyData::ASYMMETRIC_PRIVATE,
             keyset.get());
  keyset->set_primary_key_id(42);
  NSData *serializedKeyset = TINKStringToNSData(keyset->SerializeAsString());
  NSError *error = nil;
  TINKKeysetHandle *handle = [[TINKKeysetHandle alloc] initWithNoSecretKeyset:serializedKeyset
                                                                        error:&error];

  XCTAssertNil(handle);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kFailedPrecondition);
  XCTAssertTrue([error.localizedFailureReason
      containsString:@"Cannot create KeysetHandle with secret key material"]);
}

- (void)testReadNoSecretFailForHidden {
  auto keyset = std::make_unique<Keyset>();
  Keyset::Key key;
  AddTinkKey("some_key_type", 42, key, KeyStatusType::ENABLED, KeyData::ASYMMETRIC_PUBLIC,
             keyset.get());
  for (int i = 0; i < 10; ++i) {
    AddTinkKey(absl::StrCat("more key type", i), i, key, KeyStatusType::ENABLED,
               KeyData::ASYMMETRIC_PUBLIC, keyset.get());
  }
  AddRawKey("some_other_key_type", 10, key, KeyStatusType::ENABLED, KeyData::ASYMMETRIC_PRIVATE,
            keyset.get());
  for (int i = 0; i < 10; ++i) {
    AddRawKey(absl::StrCat("more key type", i + 100), i + 100, key, KeyStatusType::ENABLED,
              KeyData::ASYMMETRIC_PUBLIC, keyset.get());
  }
  keyset->set_primary_key_id(42);
  NSData *serializedKeyset = TINKStringToNSData(keyset->SerializeAsString());
  NSError *error = nil;
  TINKKeysetHandle *handle = [[TINKKeysetHandle alloc] initWithNoSecretKeyset:serializedKeyset
                                                                        error:&error];

  XCTAssertNil(handle);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kFailedPrecondition);
  XCTAssertTrue([error.localizedFailureReason
      containsString:@"Cannot create KeysetHandle with secret key material"]);
}

- (void)testSerializedKeysetNoSecret {
  NSError *error = nil;
  TINKSignatureKeyTemplate *keyTemplate =
      [[TINKSignatureKeyTemplate alloc] initWithKeyTemplate:TINKEcdsaP256 error:&error];
  XCTAssertNotNil(keyTemplate);
  XCTAssertNil(error);

  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initWithKeyTemplate:keyTemplate error:&error];
  XCTAssertNotNil(handle);
  XCTAssertNil(error);

  TINKKeysetHandle *publicHandle = [TINKKeysetHandle publicKeysetHandleWithHandle:handle
                                                                            error:&error];
  XCTAssertNotNil(publicHandle);
  XCTAssertNil(error);

  NSData *serializedKeysetNoSecret = [publicHandle serializedKeysetNoSecret:&error];
  XCTAssertNotNil(serializedKeysetNoSecret);
  XCTAssertNil(error);

  StatusOr<SecretData> testCCSerializedKeyset = SerializeKeysetToProtoKeysetFormat(
      *publicHandle.ccKeysetHandle, InsecureSecretKeyAccess::Get());
  XCTAssertTrue(testCCSerializedKeyset.ok());
  NSData *testSerializedKeyset =
      TINKStringViewToNSData(SecretDataAsStringView(*testCCSerializedKeyset));
  XCTAssertEqualObjects(serializedKeysetNoSecret, testSerializedKeyset);
}

- (void)testSerializedKeysetNoSecretFailsWithSecretMaterial {
  NSError *error = nil;
  TINKSignatureKeyTemplate *keyTemplate =
      [[TINKSignatureKeyTemplate alloc] initWithKeyTemplate:TINKEcdsaP256 error:&error];
  XCTAssertNotNil(keyTemplate);
  XCTAssertNil(error);

  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initWithKeyTemplate:keyTemplate error:&error];
  XCTAssertNotNil(handle);
  XCTAssertNil(error);

  NSData *serializedKeysetNoSecret = [handle serializedKeysetNoSecret:&error];
  XCTAssertNil(serializedKeysetNoSecret);
  XCTAssertNotNil(error);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kFailedPrecondition);
  XCTAssertTrue([error.localizedFailureReason
      containsString:@"Cannot create KeysetHandle with secret key material"]);
}

@end
