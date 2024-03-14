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

#import "Tink/TINKKeyTemplate.h"
#import "Tink/core/TINKKeyTemplate_Internal.h"
#import "Tink/util/TINKErrors.h"

#include "absl/status/status.h"
#include "tink/hybrid/hybrid_key_templates.h"
#include "tink/util/status.h"
#include "Tink/proto_redirect/tink_cc_pb_redirect.h"

@implementation TINKHybridKeyTemplate

- (nullable instancetype)initWithKeyTemplate:(TINKHybridKeyTemplates)keyTemplate
                                       error:(NSError **)error {
  google::crypto::tink::KeyTemplate *ccKeyTemplate = NULL;
  switch (keyTemplate) {
    case TINKEciesP256HkdfHmacSha256Aes128Gcm:
      ccKeyTemplate = const_cast<google::crypto::tink::KeyTemplate *>(
          &crypto::tink::HybridKeyTemplates::EciesP256HkdfHmacSha256Aes128Gcm());
      break;
    case TINKEciesP256HkdfHmacSha256Aes128CtrHmacSha256:
      ccKeyTemplate = const_cast<google::crypto::tink::KeyTemplate *>(
          &crypto::tink::HybridKeyTemplates::EciesP256HkdfHmacSha256Aes128CtrHmacSha256());
      break;
    case TINKHpkeX25519HkdfSha256Aes256Gcm:
      ccKeyTemplate = const_cast<google::crypto::tink::KeyTemplate *>(
          &crypto::tink::HybridKeyTemplates::HpkeX25519HkdfSha256Aes256Gcm());
      break;
    default:
      if (error) {
        *error = TINKStatusToError(crypto::tink::util::Status(
            absl::StatusCode::kInvalidArgument, "Invalid TINKHybridKeyTemplate"));
      }
      return nil;
  }
  return (self = [super initWithCcKeyTemplate:ccKeyTemplate]);
}

@end
