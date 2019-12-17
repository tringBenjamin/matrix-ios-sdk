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

#import "MXKeyVerificationRequest_Private.h"
#import "MXKeyVerificationByDMRequest.h"
#import "MXKeyVerificationRequestJSONModel.h"

#import "MXSession.h"
#import "MXDeviceVerificationManager_Private.h"
#import "MXCrypto_Private.h"


#pragma mark - Constants

NSString *const MXDeviceVerificationManagerNewRequestNotification = @"MXDeviceVerificationManagerNewRequestNotification";
NSString *const MXDeviceVerificationManagerNotificationRequestKey = @"MXDeviceVerificationManagerNotificationRequestKey";

// Timeout in seconds
NSTimeInterval const MXKeyVerificationRequesDefaultTimeout = 5 * 60.0;


@interface MXKeyVerificationRequestManager()
{
    // All pending requests
    // Request id -> request
    NSMutableDictionary<NSString*, MXKeyVerificationRequest*> *pendingRequestsMap;

    // Timer to cancel requests
    NSTimer *timeoutTimer;
}

@property (nonatomic, readonly, weak) MXDeviceVerificationManager *verificationManager;

@end


@implementation MXKeyVerificationRequestManager


#pragma mark - Network calls

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

    MXEvent *event = nil;
    [room sendMessageWithContent:request.JSONDictionary localEcho:&event success:^(NSString *eventId) {
        NSLog(@"[MXKeyVerificationRequest] requestVerificationByDMWithUserId: -> Request event id: %@", eventId);

        MXKeyVerificationRequest *request = [self verificationRequestInDMEvent:event];
        request.state = MXKeyVerificationRequestStatePending;
        [self addPendingRequest:request notify:NO];

        success(eventId);
        
    } failure:failure];

    NSLog(@"%@", event);
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
                   withCancelCode:(MXTransactionCancelCode*)cancelCode
                          success:(void(^)(void))success
                          failure:(void(^)(NSError *error))failure
{
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

        [self removePendingRequestWithRequestId:request.requestId];
    }
    else
    {
        // Requests by to_device are not supported
        NSParameterAssert(NO);
    }
}


- (void)resolveStateForRequest:(MXKeyVerificationRequest*)request
                       success:(void(^)(MXKeyVerificationRequestState state))success
                       failure:(void(^)(NSError *error))failure
{
    if ([request isKindOfClass:MXKeyVerificationByDMRequest.class])
    {
        MXKeyVerificationByDMRequest *requestByDM = (MXKeyVerificationByDMRequest*)request;
        [self resolveStateForRequestByDM:requestByDM success:success failure:failure];
    }
    else
    {
        // Requests by to_device are not supported
        NSParameterAssert(NO);
    }
}


#pragma mark - Current requests

- (NSArray<MXKeyVerificationRequest*> *)pendingRequests
{
    return pendingRequestsMap.allValues;
}


#pragma mark - Listener

- (id)listenToVerificationRequestStateUpdate:(MXKeyVerificationRequest *)request request:(void (^)(MXKeyVerificationRequest *request))block;
{
    return nil;
}

- (void)removeListener:(id)listener
{

}



#pragma mark - Verification request by BM

- (nullable MXHTTPOperation*)verificationByDMRequestFromEventId:(NSString*)eventId
                                                         roomId:(NSString*)roomId
                                                        success:(void(^)(MXKeyVerificationRequest *request))success
                                                        failure:(void(^)(NSError *error))failure
{
    return nil;
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
        _requestTimeout = MXKeyVerificationRequesDefaultTimeout;
        pendingRequestsMap = [NSMutableDictionary dictionary];

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
        if (direction == MXTimelineDirectionForwards
            && [event.content[@"msgtype"] isEqualToString:kMXMessageTypeKeyVerificationRequest])
        {
            NSLog(@"### %@", self.verificationManager.crypto.mxSession.myUser.userId);
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

    BOOL isFromMyUser = [request.sender isEqualToString:self.verificationManager.crypto.mxSession.myUser.userId];
    request.isFromMyUser = isFromMyUser;

    dispatch_async(dispatch_get_main_queue(), ^{
        // This is a live event, we should have all data
        [self resolveStateForRequest:request success:^(MXKeyVerificationRequestState state) {

            if (state == MXKeyVerificationRequestStatePending)
            {
                [self addPendingRequest:request notify:YES];
            }

        } failure:^(NSError *error) {
            NSLog(@"[MXKeyVerificationRequest] handleKeyVerificationRequest: Failed to resolve state: %@", request.requestId);
        }];
    });
}


#pragma mark - Requests management

- (nullable MXKeyVerificationRequest*)pendingRequestWithRequestId:(NSString*)requestId
{
    return pendingRequestsMap[requestId];
}

- (void)addPendingRequest:(MXKeyVerificationRequest *)request notify:(BOOL)notify
{
    NSLog(@"### add  %@", self.verificationManager.crypto.mxSession.myUser.userId);
    if (!pendingRequestsMap[request.requestId])
    {
        pendingRequestsMap[request.requestId] = request;

        if (notify)
        {
            NSLog(@"### Post  %@", self.verificationManager.crypto.mxSession.myUser.userId);

            [[NSNotificationCenter defaultCenter] postNotificationName:MXDeviceVerificationManagerNewRequestNotification object:self userInfo:
             @{
               MXDeviceVerificationManagerNotificationRequestKey: request
               }];
        }
    }
    [self scheduleTimeoutTimer];
}

- (void)removePendingRequestWithRequestId:(NSString*)requestId
{
    if (!pendingRequestsMap[requestId])
    {
        [pendingRequestsMap removeObjectForKey:requestId];
        [self scheduleTimeoutTimer];
    }
}


#pragma mark - Timeout management

- (nullable NSDate*)oldestRequestDate
{
    NSDate *oldestRequestDate;
    for (MXKeyVerificationRequest *request in pendingRequestsMap.allValues)
    {
        if (!oldestRequestDate
            || request.ageLocalTs < oldestRequestDate.timeIntervalSince1970)
        {
            oldestRequestDate = [NSDate dateWithTimeIntervalSince1970:(request.ageLocalTs / 1000)];
        }
    }
    return oldestRequestDate;
}

- (BOOL)isRequestStillPending:(MXKeyVerificationRequest*)request
{
    NSDate *requestDate = [NSDate dateWithTimeIntervalSince1970:(request.ageLocalTs / 1000)];
    return (requestDate.timeIntervalSinceNow > -_requestTimeout);
}

- (void)scheduleTimeoutTimer
{
    if (timeoutTimer)
    {
        if (!pendingRequestsMap.count)
        {
            NSLog(@"[MXKeyVerificationRequest] scheduleTimeoutTimer: Disable timer as there is no more requests");
            [timeoutTimer invalidate];
            timeoutTimer = nil;
        }

        return;
    }

    NSDate *oldestRequestDate = [self oldestRequestDate];
    if (oldestRequestDate)
    {
        NSLog(@"[MXKeyVerificationRequest] scheduleTimeoutTimer: Create timer");

        NSDate *timeoutDate = [oldestRequestDate dateByAddingTimeInterval:self.requestTimeout];
        self->timeoutTimer = [[NSTimer alloc] initWithFireDate:timeoutDate
                                                      interval:0
                                                        target:self
                                                      selector:@selector(onTimeoutTimer)
                                                      userInfo:nil
                                                       repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:self->timeoutTimer forMode:NSDefaultRunLoopMode];
    }
}

- (void)onTimeoutTimer
{
    NSLog(@"[MXKeyVerificationRequest] onTimeoutTimer");
    timeoutTimer = nil;

    [self checkTimeouts];
    [self scheduleTimeoutTimer];
}

- (void)checkTimeouts
{
    for (MXKeyVerificationRequest *request in pendingRequestsMap.allValues)
    {
        if ([self isRequestStillPending:request])
        {
            NSLog(@"[MXKeyVerificationRequest] checkTimeouts: timeout %@", request);

            [self cancelVerificationRequest:request withCancelCode:MXTransactionCancelCode.timeout success:^{

            } failure:^(NSError * _Nonnull error) {
                NSLog(@"[MXKeyVerificationRequest] checkTimeouts. Failed to cancel request: %@. Error: %@", request.requestId, error);
            }];
        }
    }
}


#pragma mark - State resolver

- (void)resolveStateForRequestByDM:(MXKeyVerificationByDMRequest*)request
                           success:(void(^)(MXKeyVerificationRequestState state))success
                           failure:(void(^)(NSError *error))failure
{
    NSLog(@"### resolve  %@", self.verificationManager.crypto.mxSession.myUser.userId);

    // Get all related events
    [_verificationManager.crypto.mxSession.aggregations referenceEventsForEvent:request.eventId inRoom:request.roomId from:nil limit:-1 success:^(MXAggregationPaginatedResponse * _Nonnull paginatedResponse) {

        NSLog(@"### resolve  %@", self.verificationManager.crypto.mxSession.myUser.userId);

        MXKeyVerificationRequestState state = MXKeyVerificationRequestStatePending;

        for (MXEvent *event in paginatedResponse.chunk)
        {
            NSLog(@"### # %@", event);
        }

        if (state == MXKeyVerificationRequestStatePending
            && ![self isRequestStillPending:request])
        {
            // Check expiration
            state = MXKeyVerificationRequestStateExpired;
        }

        request.state = state;
        success(state);

    } failure:failure];
}

@end
