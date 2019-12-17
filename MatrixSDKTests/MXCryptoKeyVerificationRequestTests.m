/*
 * Copyright 2019 New Vector Ltd
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
 */

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"
#import "MatrixSDKTestsE2EData.h"

#import "MXCrypto_Private.h"
#import "MXDeviceVerificationManager_Private.h"

#import "MXKeyVerificationRequestJSONModel.h"

// Do not bother with retain cycles warnings in tests
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"


@interface MXCryptoKeyVerificationRequestTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
    MatrixSDKTestsE2EData *matrixSDKTestsE2EData;

    NSMutableArray<id> *observers;
}
@end

@implementation MXCryptoKeyVerificationRequestTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
    matrixSDKTestsE2EData = [[MatrixSDKTestsE2EData alloc] initWithMatrixSDKTestsData:matrixSDKTestsData];

    observers = [NSMutableArray array];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;
    matrixSDKTestsE2EData = nil;

    for (id observer in observers)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }

    [super tearDown];
}


- (void)observeKeyVerificationRequestInSession:(MXSession*)session block:(void (^)(MXKeyVerificationRequest * _Nullable request))block
{
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXDeviceVerificationManagerNewRequestNotification object:session.crypto.deviceVerificationManager.requestManager queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {

        MXKeyVerificationRequest *request = notif.userInfo[MXDeviceVerificationManagerNotificationRequestKey];
        if ([request isKindOfClass:MXKeyVerificationRequest.class])
        {
            block((MXKeyVerificationRequest*)request);
        }
        else
        {
            XCTFail(@"We support only SAS. transaction: %@", request);
        }
    }];

    [observers addObject:observer];
}

//
//- (void)observeTransactionUpdate:(MXDeviceVerificationTransaction*)transaction block:(void (^)(void))block
//{
//    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:MXDeviceVerificationTransactionDidChangeNotification object:transaction queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
//            block();
//    }];
//
//    [observers addObject:observer];
//}
//


# pragma mark - Request by DM -

/**
 Test new requests

 - Alice and Bob are in a room
 - Bob requests a verification of Alice in this Room
 -> Alice gets the requests notification
 -> They both have it in their pending requests



 - Alice accepts it and begins a SAS verification
 -> 1. Transaction on Bob side must be WaitForPartnerKey (Alice is WaitForPartnerToAccept)
 -> 2. Transaction on Alice side must then move to WaitForPartnerKey
 -> 3. Transaction on Bob side must then move to ShowSAS
 -> 4. Transaction on Alice side must then move to ShowSAS
 -> 5. SASs must be the same
 -  Alice confirms SAS
 -> 6. Transaction on Alice side must then move to WaitForPartnerToConfirm
 -  Bob confirms SAS
 -> 7. Transaction on Bob side must then move to Verified
 -> 7. Transaction on Alice side must then move to Verified
 -> Devices must be really verified
 -> Transaction must not be listed anymore
 -> Both ends must get a done message
 */
- (void)testVerificationByDMFullFlow
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *fallbackText = @"fallbackText";
        __block NSString *requestEventId;

        MXCredentials *alice = aliceSession.matrixRestClient.credentials;
        MXCredentials *bob = bobSession.matrixRestClient.credentials;

        // - Bob requests a verification of Alice in this Room
        [bobSession.crypto.deviceVerificationManager.requestManager requestVerificationByDMWithUserId:alice.userId
                                                                                               roomId:roomId
                                                                                         fallbackText:fallbackText
                                                                                              methods:@[MXKeyVerificationMethodSAS, @"toto"]
                                                                                              success:^(NSString * _Nonnull eventId)
         {
             requestEventId = eventId;
         }
                                                                               failure:^(NSError * _Nonnull error)
         {
             XCTFail(@"The request should not fail - NSError: %@", error);
             [expectation fulfill];
         }];


        // -> Alice gets the requests notification
        [self observeKeyVerificationRequestInSession:aliceSession block:^(MXKeyVerificationRequest * _Nullable request) {
            XCTAssertEqualObjects(request.requestId, requestEventId);
            XCTAssertFalse(request.isFromMyUser);

            MXKeyVerificationRequest *requestFromAlicePOV = aliceSession.crypto.deviceVerificationManager.requestManager.pendingRequests.firstObject;
            MXKeyVerificationRequest *requestFromBobPOV = bobSession.crypto.deviceVerificationManager.requestManager.pendingRequests.firstObject;

            XCTAssertNotNil(requestFromAlicePOV);
            XCTAssertNotNil(requestFromBobPOV);


            [expectation fulfill];
        }];

//        // - Bob gets also the requests notification
//        dispatch_group_enter(group);
//        [self observeKeyVerificationRequestInSession:bobSession block:^(MXKeyVerificationRequest * _Nullable request) {
//            XCTAssertEqualObjects(request.requestId, requestEventId);
//            XCTAssertTrue(request.isFromMyUser);
//            dispatch_group_leave(group);
//        }];
//
//        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
//            [expectation fulfill];
//        });

        /*


        __block MXOutgoingSASTransaction *sasTransactionFromAlicePOV;


        // Alice gets the request in the timeline
        [aliceSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                  onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject)
         {
             if ([event.content[@"msgtype"] isEqualToString:kMXMessageTypeKeyVerificationRequest])
             {
                 XCTAssertEqualObjects(event.eventId, requestEventId);

                 // Check verification by DM request format
                 MXKeyVerificationRequestJSONModel *JSONRequest;
                 MXJSONModelSetMXJSONModel(JSONRequest, MXKeyVerificationRequestJSONModel.class, event.content);
                 XCTAssertNotNil(JSONRequest);

                 MXKeyVerificationRequest *request = [aliceSession.crypto.deviceVerificationManager.requestManager verificationRequestInDMEvent:event];
                 XCTAssertNotNil(request);

                 // - Alice accepts it and begins a SAS verification
                 [aliceSession.crypto.deviceVerificationManager.requestManager acceptVerificationRequest:request method:MXKeyVerificationMethodSAS success:^(MXDeviceVerificationTransaction * _Nonnull transactionFromAlicePOV) {

                     XCTAssertEqualObjects(transactionFromAlicePOV.transactionId, event.eventId);

                     XCTAssert(transactionFromAlicePOV);
                     XCTAssertTrue([transactionFromAlicePOV isKindOfClass:MXOutgoingSASTransaction.class]);
                     sasTransactionFromAlicePOV = (MXOutgoingSASTransaction*)transactionFromAlicePOV;

                 } failure:^(NSError * _Nonnull error) {
                     XCTFail(@"The request should not fail - NSError: %@", error);
                     [expectation fulfill];
                 }];
             }
         }];



        // -> Both ends must get a done message
        NSMutableArray<MXKeyVerificationDone*> *doneDone = [NSMutableArray new];
        void (^checkDoneDone)(MXEvent *event, MXTimelineDirection direction, id customObject) = ^ void (MXEvent *event, MXTimelineDirection direction, id customObject)
        {
            XCTAssertEqual(event.eventType, MXEventTypeKeyVerificationDone);

            // Check done format
            MXKeyVerificationDone *done;
            MXJSONModelSetMXJSONModel(done, MXKeyVerificationDone.class, event.content);
            XCTAssertNotNil(done);

            [doneDone addObject:done];
            if (doneDone.count == 2)
            {
                [expectation fulfill];
            }
        };

        [aliceSession listenToEventsOfTypes:@[kMXEventTypeStringKeyVerificationDone]
                                    onEvent:checkDoneDone];
        [bobSession listenToEventsOfTypes:@[kMXEventTypeStringKeyVerificationDone]
                                    onEvent:checkDoneDone];

         */
    }];
}


/**
 Nomical case: The full flow
 It reuses code from testFullFlowWithAliceAndBob.

 - Alice and Bob are in a room
 - Bob requests a verification of Alice in this Room
 - Alice gets the request in the timeline
 - Alice rejects the incoming request
 -> Both ends must see a cancel message
 */
- (void)testVerificationByDMCancelledByAlice
{
    // - Alice and Bob are in a room
    [matrixSDKTestsE2EData doE2ETestWithAliceAndBobInARoomWithCryptedMessages:self cryptedBob:YES readyToTest:^(MXSession *aliceSession, MXSession *bobSession, NSString *roomId, XCTestExpectation *expectation) {

        NSString *fallbackText = @"fallbackText";
        __block NSString *requestEventId;

        MXCredentials *alice = aliceSession.matrixRestClient.credentials;

        // - Bob requests a verification of Alice in this Room
        [bobSession.crypto.deviceVerificationManager.requestManager requestVerificationByDMWithUserId:alice.userId
                                                                                               roomId:roomId
                                                                                         fallbackText:fallbackText
                                                                                              methods:@[MXKeyVerificationMethodSAS, @"toto"]
                                                                                              success:^(NSString * _Nonnull eventId)
         {
             requestEventId = eventId;
         }
                                                                               failure:^(NSError * _Nonnull error)
         {
             XCTFail(@"The request should not fail - NSError: %@", error);
             [expectation fulfill];
         }];

        // Alice gets the request in the timeline
        [aliceSession listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage]
                                    onEvent:^(MXEvent *event, MXTimelineDirection direction, id customObject)
         {
             if ([event.content[@"msgtype"] isEqualToString:kMXMessageTypeKeyVerificationRequest])
             {
                 MXKeyVerificationRequestJSONModel *JSONRequest;
                 MXJSONModelSetMXJSONModel(JSONRequest, MXKeyVerificationRequestJSONModel.class, event.content);
                 XCTAssertNotNil(JSONRequest);

                 MXKeyVerificationRequest *request = [aliceSession.crypto.deviceVerificationManager.requestManager verificationRequestInDMEvent:event];
                 XCTAssertNotNil(request);

                  // - Alice rejects the incoming request
                 [aliceSession.crypto.deviceVerificationManager.requestManager cancelVerificationRequest:request
                                                                                          withCancelCode:MXTransactionCancelCode.user success:^{

                                                                                          } failure:^(NSError * _Nonnull error) {

                                                                                          }];
             }
         }];

        // -> Both ends must see a cancel message
        NSMutableArray<MXKeyVerificationCancel*> *cancelCancel = [NSMutableArray new];
        void (^checkCancelCancel)(MXEvent *event, MXTimelineDirection direction, id customObject) = ^ void (MXEvent *event, MXTimelineDirection direction, id customObject)
        {
            XCTAssertEqual(event.eventType, MXEventTypeKeyVerificationCancel);

            // Check cancel format
            MXKeyVerificationCancel *cancel;
            MXJSONModelSetMXJSONModel(cancel, MXKeyVerificationCancel.class, event.content);
            XCTAssertNotNil(cancel);

            [cancelCancel addObject:cancel];
            if (cancelCancel.count == 2)
            {
                [expectation fulfill];
            }
        };

        [aliceSession listenToEventsOfTypes:@[kMXEventTypeStringKeyVerificationCancel]
                                    onEvent:checkCancelCancel];
        [bobSession listenToEventsOfTypes:@[kMXEventTypeStringKeyVerificationCancel]
                                  onEvent:checkCancelCancel];
    }];
}

@end
