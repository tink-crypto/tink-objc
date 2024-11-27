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

#import "Tink/TINKJSONKeysetReader.h"

#import "Tink/TINKKeysetReader.h"
#import "Tink/core/TINKKeysetReader_Internal.h"
#import "Tink/util/TINKErrors.h"
#import "Tink/util/TINKStrings.h"

#include "absl/status/status.h"
#include "absl/strings/string_view.h"
#include "tink/json/json_keyset_reader.h"
#include "Tink/proto_redirect/tink_cc_pb_redirect.h"

@implementation TINKJSONKeysetReader

- (instancetype)initWithSerializedKeyset:(NSData *)keyset error:(NSError **)error {
  if (keyset == nil) {
    if (error) {
      *error = TINKStatusToError(crypto::tink::util::Status(
          absl::StatusCode::kInvalidArgument, "keyset must be non-nil."));
    }
    return nil;
  }

  if (self = [super init]) {
    auto st = crypto::tink::JsonKeysetReader::New(absl::string_view(
        reinterpret_cast<const char *>(keyset.bytes), static_cast<size_t>(keyset.length)));
    if (!st.ok()) {
      if (error) {
        *error = TINKStatusToError(st.status());
      }
      return nil;
    }
    self.ccReader = std::move(st.value());
    self.used = NO;
  }
  return self;
}

@end
