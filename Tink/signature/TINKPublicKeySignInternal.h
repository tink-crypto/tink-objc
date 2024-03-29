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

#ifdef __cplusplus

#import "Tink/TINKPublicKeySign.h"

#import <Foundation/Foundation.h>

#include "tink/public_key_sign.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * This interface is internal-only. Use TINKPublicKeySignFactory to get an instance that conforms to
 * TINKPublicKeySign.
 */
@interface TINKPublicKeySignInternal : NSObject <TINKPublicKeySign>

- (instancetype)init NS_UNAVAILABLE;

- (nullable instancetype)initWithCCPublicKeySign:
    (std::unique_ptr<crypto::tink::PublicKeySign>)ccPublicKeySign NS_DESIGNATED_INITIALIZER;

- (nullable crypto::tink::PublicKeySign *)ccPublicKeySign;

@end

NS_ASSUME_NONNULL_END

#endif  // __cplusplus
