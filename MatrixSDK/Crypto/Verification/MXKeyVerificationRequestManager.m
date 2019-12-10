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

#import "MXKeyVerificationRequestManager_Private.h"

#import "MXKeyVerificationByDMRequest.h"
#import "MXKeyVerificationRequestJSONModel.h"

#import "MXSession.h"
#import "MXDeviceVerificationManager_Private.h"
#import "MXCrypto_Private.h"


@interface MXKeyVerificationRequestManager()
@property (nonatomic, readonly, weak) MXDeviceVerificationManager *verificationManager;
@end


@implementation MXKeyVerificationRequestManager


- (void)requestVerificationByDMWithUserId:(NSString*)userId
                                   roomId:(NSString*)roomId
                             fallbackText:(NSString*)fallbackText
                                  methods:(NSArray<NSString*>*)methods
                                  success:(void(^)(NSString *eventId))success
                                  failure:(void(^)(NSError *error))failure
{
    NSLog(@"[MXKeyVerificationRequest] requestVerificationByDMWithUserId: %@. RoomId: %@", userId, roomId);

    MXRoom *room = [_verificationManager.crypto.mxSession roomWithRoomId:roomId];
    if (!room)
    {
        NSError *error = [NSError errorWithDomain:MXDeviceVerificationErrorDomain
                                             code:MXDeviceVerificationUnknownRoomCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown room: %@", roomId]
                                                    }];
        failure(error);
        return;
    }

    MXKeyVerificationRequestJSONModel *request = [MXKeyVerificationRequestJSONModel new];
    request.body = fallbackText;
    request.methods = methods;
    request.to = userId;
    request.fromDevice = _verificationManager.crypto.myDevice.deviceId;

    [room sendMessageWithContent:request.JSONDictionary localEcho:nil success:^(NSString *eventId) {
        NSLog(@"[MXKeyVerificationRequest] requestVerificationByDMWithUserId: -> Request event id: %@", eventId);
        success(eventId);
    } failure:failure];
}


- (void)acceptVerificationRequest:(MXKeyVerificationRequest*)request
                           method:(NSString*)method
                          success:(void(^)(MXDeviceVerificationTransaction *transaction))success
                          failure:(void(^)(NSError *error))failure
{
    NSLog(@"[MXKeyVerificationRequest] acceptVerificationRequest: event: %@", request.requestId);

    // Sanity checks
    NSString *fromDevice = request.fromDevice;
    if (!fromDevice)
    {
        NSError *error = [NSError errorWithDomain:MXDeviceVerificationErrorDomain
                                             code:MXDeviceVerificationUnknownDeviceCode
                                         userInfo:@{
                                                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"from_device not found"]
                                                    }];
        failure(error);
        return;
    }

    if ([request isKindOfClass:MXKeyVerificationByDMRequest.class])
    {
        MXKeyVerificationByDMRequest *requestByDM = (MXKeyVerificationByDMRequest*)request;
        [_verificationManager beginKeyVerificationWithUserId:request.sender andDeviceId:fromDevice dmRoomId:requestByDM.roomId dmEventId:requestByDM.eventId method:method success:success failure:failure];
    }
    else
    {
        // Requests by to_device are not supported
        NSParameterAssert(NO);
    }
}

- (void)cancelVerificationRequest:(MXKeyVerificationRequest*)request
                          success:(void(^)(void))success
                          failure:(void(^)(NSError *error))failure
{
    MXTransactionCancelCode *cancelCode = MXTransactionCancelCode.user;

    // Else only cancel the request
    if ([request isKindOfClass:MXKeyVerificationByDMRequest.class])
    {
        MXKeyVerificationByDMRequest *requestByDM = (MXKeyVerificationByDMRequest*)request;

        MXKeyVerificationCancel *cancel = [MXKeyVerificationCancel new];
        cancel.transactionId = request.requestId;
        cancel.code = cancelCode.value;
        cancel.reason = cancelCode.humanReadable;

        [_verificationManager sendMessage:request.sender roomId:requestByDM.roomId eventType:kMXEventTypeStringKeyVerificationCancel relatedTo:requestByDM.eventId content:cancel.JSONDictionary success:^{} failure:^(NSError *error) {

            NSLog(@"[MXKeyVerification] cancelTransactionFromStartEvent. Error: %@", error);
        }];
    }
    else
    {
        // Requests by to_device are not supported
        NSParameterAssert(NO);
    }
}


- (nullable MXKeyVerificationRequest*)verificationRequestInDMEvent:(MXEvent*)event
{
    MXKeyVerificationRequest *request;
    if ([event.content[@"msgtype"] isEqualToString:kMXMessageTypeKeyVerificationRequest])
    {
        request = [[MXKeyVerificationByDMRequest alloc] initWithEvent:event];
    }
    return request;
}


#pragma mark - SDK-Private methods -

- (instancetype)initWithVerificationManager:(MXDeviceVerificationManager*)verificationManager
{
    self = [super init];
    if (self)
    {
        _verificationManager = verificationManager;

        [self setupVericationByDMRequests];
    }
    return self;
}


#pragma mark - Private methods -

- (void)setupVericationByDMRequests
{
    NSArray *types = @[
                       kMXEventTypeStringRoomMessage
                       ];

    [_verificationManager.crypto.mxSession listenToEventsOfTypes:types onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject) {
        // TODO: Check time
        if (direction == MXTimelineDirectionForwards
            && ![event.sender isEqualToString:self.verificationManager.crypto.mxSession.myUser.userId]
            && [event.content[@"msgtype"] isEqualToString:kMXMessageTypeKeyVerificationRequest])
        {
            MXKeyVerificationByDMRequest *requestByDM = [[MXKeyVerificationByDMRequest alloc] initWithEvent:event];
            if (requestByDM)
            {
                [self handleKeyVerificationRequest:requestByDM];
            }
        }
    }];
}

- (void)handleKeyVerificationRequest:(MXKeyVerificationRequest*)request
{
    NSLog(@"[MXKeyVerificationRequest] handleKeyVerificationRequest: %@", request);

    if (![request.to isEqualToString:self.verificationManager.crypto.mxSession.myUser.userId])
    {
        NSLog(@"[MXKeyVerificationRequest] handleKeyVerificationRequest: Request for another user: %@", request.to);
        return;
    }

    // TODO
}

@end
