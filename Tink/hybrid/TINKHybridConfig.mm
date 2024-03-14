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

#import "Tink/TINKHybridConfig.h"

#import "Tink/TINKRegistryConfig.h"
#import "Tink/util/TINKErrors.h"

#include "tink/hybrid/hpke_config.h"
#include "tink/hybrid/hybrid_config.h"
#include "tink/util/status.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
@implementation TINKHybridConfig

- (nullable instancetype)initWithError:(NSError **)error {
  auto st = crypto::tink::HybridConfig::Register();
  if (!st.ok()) {
    if (error) {
      *error = TINKStatusToError(st);
    }
    return nil;
  }

  st = crypto::tink::RegisterHpke();
  if (!st.ok()) {
    if (error) {
      *error = TINKStatusToError(st);
    }
    return nil;
  }

  return (self = [super initWithError:error]);
}

@end
#pragma clang diagnostic pop
