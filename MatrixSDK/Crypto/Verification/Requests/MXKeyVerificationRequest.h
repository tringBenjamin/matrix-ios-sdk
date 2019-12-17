/*
 Copyright 2019 The Matrix.org Foundation C.I.C

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import <Foundation/Foundation.h>

#pragma mark - Constants

/**
 Notification sent when the request has been updated.
 */
FOUNDATION_EXPORT NSString * _Nonnull const MXKeyVerificationRequestDidChangeNotification;

typedef enum : NSUInteger
{
    MXKeyVerificationRequestStateUnkwnown = 0,      // The state is not fully computed yet
    MXKeyVerificationRequestStatePending,
    MXKeyVerificationRequestStateExpired,
    MXKeyVerificationRequestStateCancelled,
    MXKeyVerificationRequestStateCancelledByMe,
    MXKeyVerificationRequestStateAccepted
} MXKeyVerificationRequestState;


NS_ASSUME_NONNULL_BEGIN

/**
 An handler on an interactive verification request.
 */
@interface MXKeyVerificationRequest : NSObject

@property (nonatomic, readonly) NSString *requestId;

@property (nonatomic, readonly) BOOL isFromMyUser;

@property (nonatomic) NSString *to;

@property (nonatomic, readonly) NSString *sender;
@property (nonatomic, readonly) NSString *fromDevice;

@property (nonatomic, readonly) NSUInteger age;
@property (nonatomic, readonly) uint64_t ageLocalTs;

@property (nonatomic, readonly) MXKeyVerificationRequestState state;

@end

NS_ASSUME_NONNULL_END
