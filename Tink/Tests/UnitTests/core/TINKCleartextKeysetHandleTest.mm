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

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#include <memory>
#include <string>
#include <utility>

#import "Tink/TINKBinaryKeysetReader.h"
#import "Tink/TINKKeysetHandle+Cleartext.h"
#import "Tink/TINKKeysetHandle.h"
#import "Tink/core/TINKKeysetHandle_Internal.h"
#import "Tink/util/TINKStrings.h"

#include "absl/status/status.h"
#include "tink/insecure_secret_key_access.h"
#include "tink/proto_keyset_format.h"
#include "tink/secret_data.h"
#include "tink/util/secret_data.h"
#include "tink/util/statusor.h"
#include "tink/util/test_util.h"
#include "Tink/proto_redirect/tink_cc_pb_redirect.h"

using ::crypto::tink::InsecureSecretKeyAccess;
using ::crypto::tink::SerializeKeysetToProtoKeysetFormat;
using ::crypto::tink::SecretData;
using ::crypto::tink::util::SecretDataAsStringView;
using ::crypto::tink::util::StatusOr;

@interface TINKCleartextKeysetHandleTest : XCTestCase
@end

@implementation TINKCleartextKeysetHandleTest

- (void)testReadValidKeyset {
  google::crypto::tink::Keyset keyset;
  google::crypto::tink::Keyset::Key key;
  crypto::tink::test::AddTinkKey("some_key_type", 42, key,
                                 google::crypto::tink::KeyStatusType::ENABLED,
                                 google::crypto::tink::KeyData::SYMMETRIC, &keyset);
  crypto::tink::test::AddRawKey("some_other_key_type", 711, key,
                                google::crypto::tink::KeyStatusType::ENABLED,
                                google::crypto::tink::KeyData::SYMMETRIC, &keyset);
  keyset.set_primary_key_id(42);

  NSData *serializedKeyset = TINKStringToNSData(keyset.SerializeAsString());

  NSError *error = nil;
  TINKBinaryKeysetReader *reader =
      [[TINKBinaryKeysetReader alloc] initWithSerializedKeyset:serializedKeyset error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(reader);

  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initCleartextKeysetHandleWithKeysetReader:reader error:&error];

  XCTAssertNotNil(handle);
  StatusOr<SecretData> serialized =
      SerializeKeysetToProtoKeysetFormat(*handle.ccKeysetHandle, InsecureSecretKeyAccess::Get());
  XCTAssertTrue(serialized.ok());
  XCTAssertEqualObjects(TINKStringViewToNSData(SecretDataAsStringView(*serialized)),
                        TINKStringViewToNSData(keyset.SerializeAsString()));

  // Trying to use the same reader again must fail.
  error = nil;
  XCTAssertNil(
      [[TINKKeysetHandle alloc] initCleartextKeysetHandleWithKeysetReader:reader error:&error]);
  XCTAssertNotNil(error);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kResourceExhausted);
  XCTAssertTrue(
      [error.localizedFailureReason containsString:@"A KeysetReader can be used only once."]);
}

- (void)testReadInvalidKeyset {
  NSError *error = nil;
  TINKBinaryKeysetReader *reader = [[TINKBinaryKeysetReader alloc]
      initWithSerializedKeyset:[@"invalid serialized keyset" dataUsingEncoding:NSUTF8StringEncoding]
                         error:&error];

  XCTAssertNil(error);

  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initCleartextKeysetHandleWithKeysetReader:reader error:&error];

  XCTAssertNil(handle);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kInvalidArgument);
}

- (void)testSerializeKeyset {
  google::crypto::tink::Keyset keyset;
  google::crypto::tink::Keyset::Key key;
  crypto::tink::test::AddTinkKey("some_key_type", 42, key,
                                 google::crypto::tink::KeyStatusType::ENABLED,
                                 google::crypto::tink::KeyData::SYMMETRIC, &keyset);
  crypto::tink::test::AddRawKey("some_other_key_type", 711, key,
                                google::crypto::tink::KeyStatusType::ENABLED,
                                google::crypto::tink::KeyData::SYMMETRIC, &keyset);
  keyset.set_primary_key_id(42);

  NSData *serializedKeyset = TINKStringToNSData(keyset.SerializeAsString());

  NSError *error = nil;
  TINKBinaryKeysetReader *reader =
      [[TINKBinaryKeysetReader alloc] initWithSerializedKeyset:serializedKeyset error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(reader);

  TINKKeysetHandle *handle =
      [[TINKKeysetHandle alloc] initCleartextKeysetHandleWithKeysetReader:reader error:&error];

  XCTAssertNotNil(handle);
  XCTAssertTrue([serializedKeyset isEqualToData:handle.serializedKeyset]);
}


@end
