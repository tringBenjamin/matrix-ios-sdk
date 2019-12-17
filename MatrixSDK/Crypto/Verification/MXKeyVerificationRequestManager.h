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


#import "MXKeyVerificationRequest.h"
#import "MXTransactionCancelCode.h"

#import "MXHTTPOperation.h"

@class MXDeviceVerificationTransaction, MXEvent;


NS_ASSUME_NONNULL_BEGIN

#pragma mark - Constants

/**
 Posted on new device verification request.
 */
FOUNDATION_EXPORT NSString *const MXDeviceVerificationManagerNewRequestNotification;

/**
 The key in the notification userInfo dictionary containing the `MXKeyVerificationRequest` instance.
 */
FOUNDATION_EXPORT NSString *const MXDeviceVerificationManagerNotificationRequestKey;


@interface MXKeyVerificationRequestManager : NSObject

/**
 The timeout for requests.
 Default is 5 min.
 */
@property (nonatomic) NSTimeInterval requestTimeout;


#pragma mark - Network calls

/**
 Make a key verification request by Direct Message.

 @param userId the other user id.
 @param roomId the room to exchange direct messages
 @param fallbackText a text description if the app does not support verification by DM.
 @param methods Verification methods like MXKeyVerificationMethodSAS.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 */
- (void)requestVerificationByDMWithUserId:(NSString*)userId
                                   roomId:(NSString*)roomId
                             fallbackText:(NSString*)fallbackText
                                  methods:(NSArray<NSString*>*)methods
                                  success:(void(^)(NSString *eventId))success
                                  failure:(void(^)(NSError *error))failure;


/**
 Accept an incoming key verification request.

 @param request the request.
 @param method the method to use.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 */
- (void)acceptVerificationRequest:(MXKeyVerificationRequest*)request
                           method:(NSString*)method
                          success:(void(^)(MXDeviceVerificationTransaction *transaction))success
                          failure:(void(^)(NSError *error))failure;

/**
 Cancel a key verification request or reject an incoming key verification request.

 @param request the request.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 */
- (void)cancelVerificationRequest:(MXKeyVerificationRequest*)request
                   withCancelCode:(MXTransactionCancelCode*)cancelCode
                          success:(void(^)(void))success
                          failure:(void(^)(NSError *error))failure;


#pragma mark - Current requests

/**
 All pending verification requests.
 */
@property (nonatomic, readonly) NSArray<MXKeyVerificationRequest*> *pendingRequests;


#pragma mark - Listener

/**
 Add a listener to request state updates

 @param request The verification request to track.
 @param block The block called on updates.
 @return a listener id.
 */
- (id)listenToVerificationRequestStateUpdate:(MXKeyVerificationRequest *)request request:(void (^)(MXKeyVerificationRequest *request))block;
- (void)removeListener:(id)listener;


#pragma mark - Verification request by BM

/**
 Extract a verification request from a Direct Message.

 @param eventId the event id of the message.
 @param roomId the room id of the message.
 @param success a block called when the operation succeeds.
 @param failure a block called when the operation fails.
 @return a MXHTTPOperation instance. May be nil in case of syncronous response
 */
- (nullable MXHTTPOperation*)verificationByDMRequestFromEventId:(NSString*)eventId
                                                         roomId:(NSString*)roomId
                                                        success:(void(^)(MXKeyVerificationRequest *request))success
                                                        failure:(void(^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END
