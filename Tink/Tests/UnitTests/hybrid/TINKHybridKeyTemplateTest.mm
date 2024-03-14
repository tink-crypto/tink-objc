/**
 * Copyright 2018 Google Inc.
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

#import "Tink/TINKHybridKeyTemplate.h"

#import <XCTest/XCTest.h>

#include <memory>
#include <string>
#include <utility>

#import "Tink/TINKAeadKeyTemplate.h"
#import "Tink/TINKKeyTemplate.h"
#import "Tink/core/TINKKeyTemplate_Internal.h"
#include "proto/common.pb.h"
#include "proto/tink.pb.h"

#include "absl/status/status.h"
#include "tink/util/status.h"

@interface TINKHybridKeyTemplateTest : XCTestCase
@end

static std::string const kEciesTypeURL =
    "type.googleapis.com/google.crypto.tink.EciesAeadHkdfPrivateKey";
static std::string const kHpkeTypeURL = "type.googleapis.com/google.crypto.tink.HpkePrivateKey";

@implementation TINKHybridKeyTemplateTest

- (void)testInvalidKeyTemplate {
  NSError *error = nil;
  // Specify an invalid keyTemplate.
  TINKHybridKeyTemplate *keyTemplate =
      [[TINKHybridKeyTemplate alloc] initWithKeyTemplate:TINKHybridKeyTemplates(-1) error:&error];
  XCTAssertNotNil(error);
  XCTAssertNil(keyTemplate);
  XCTAssertEqual((absl::StatusCode)error.code, absl::StatusCode::kInvalidArgument);
  NSDictionary<NSErrorUserInfoKey, id> *userInfo = [error userInfo];
  NSString *errorString = [userInfo objectForKey:NSLocalizedFailureReasonErrorKey];
  XCTAssertTrue([errorString containsString:@"Invalid TINKHybridKeyTemplate"]);
}

- (void)testEciesP256HkdfHmacSha256Aes128Gcm {
  // Get a EciesP256HkdfHmacSha256Aes128Gcm key template.
  NSError *error = nil;
  TINKHybridKeyTemplate *keyTemplate =
      [[TINKHybridKeyTemplate alloc] initWithKeyTemplate:TINKEciesP256HkdfHmacSha256Aes128Gcm
                                                   error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(keyTemplate);

  XCTAssertTrue(keyTemplate.ccKeyTemplate->type_url() == kEciesTypeURL);
  XCTAssertTrue(keyTemplate.ccKeyTemplate->output_prefix_type() ==
                google::crypto::tink::OutputPrefixType::TINK);
}

- (void)testEciesP256HkdfHmacSha256Aes128CtrHmacSha256 {
  // Get a EciesP256HkdfHmacSha256Aes128CtrHmacSha256 key template.
  NSError *error = nil;
  TINKHybridKeyTemplate *keyTemplate = [[TINKHybridKeyTemplate alloc]
      initWithKeyTemplate:TINKEciesP256HkdfHmacSha256Aes128CtrHmacSha256
                    error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(keyTemplate);

  XCTAssertTrue(keyTemplate.ccKeyTemplate->type_url() == kEciesTypeURL);
  XCTAssertTrue(keyTemplate.ccKeyTemplate->output_prefix_type() ==
                google::crypto::tink::OutputPrefixType::TINK);
}

- (void)testHpkeX25519HkdfSha256Aes256Gcm {
  // Get a HpkeX25519HkdfSha256Aes256Gcm key template.
  NSError *error = nil;
  TINKHybridKeyTemplate *keyTemplate =
      [[TINKHybridKeyTemplate alloc] initWithKeyTemplate:TINKHpkeX25519HkdfSha256Aes256Gcm
                                                   error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(keyTemplate);

  XCTAssertTrue(keyTemplate.ccKeyTemplate->type_url() == kHpkeTypeURL);
  XCTAssertTrue(keyTemplate.ccKeyTemplate->output_prefix_type() ==
                google::crypto::tink::OutputPrefixType::TINK);
}

@end
