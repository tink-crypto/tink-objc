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

#import "Tink/TINKHybridEncryptFactory.h"

#import <Foundation/Foundation.h>

#import "Tink/TINKHybridEncrypt.h"
#import "Tink/TINKKeysetHandle.h"
#import "Tink/core/TINKKeysetHandle_Internal.h"
#import "Tink/hybrid/TINKHybridEncryptInternal.h"
#import "Tink/util/TINKErrors.h"

#include "tink/config/global_registry.h"
#include "tink/keyset_handle.h"
#include "tink/util/status.h"

@implementation TINKHybridEncryptFactory

+ (id<TINKHybridEncrypt>)primitiveWithKeysetHandle:(TINKKeysetHandle *)keysetHandle
                                             error:(NSError **)error {
  crypto::tink::KeysetHandle *handle = [keysetHandle ccKeysetHandle];

  auto st = handle->GetPrimitive<crypto::tink::HybridEncrypt>(crypto::tink::ConfigGlobalRegistry());
  if (!st.ok()) {
    if (error) {
      *error = TINKStatusToError(st.status());
    }
    return nil;
  }
  id<TINKHybridEncrypt> hybrid =
      [[TINKHybridEncryptInternal alloc] initWithCCHybridEncrypt:std::move(st.value())];
  if (!hybrid) {
    if (error) {
      *error = TINKStatusToError(crypto::tink::util::Status(
          absl::StatusCode::kResourceExhausted, "Cannot initialize TINKHybridEncrypt"));
    }
    return nil;
  }

  return hybrid;
}

@end
