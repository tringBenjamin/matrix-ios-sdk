/*
 Copyright 2020 The Matrix.org Foundation C.I.C
 
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

#import "MXSecretStoragePassphrase.h"

@implementation MXSecretStoragePassphrase

#pragma mark - MXJSONModel

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    NSString *algorithm, *salt;
    NSUInteger iterations = 0, bits = 0;
    
    MXJSONModelSetString(algorithm, JSONDictionary[@"algorithm"]);
    MXJSONModelSetUInteger(iterations, JSONDictionary[@"iterations"]);
    MXJSONModelSetString(salt, JSONDictionary[@"salt"]);
    MXJSONModelSetUInteger(bits, JSONDictionary[@"bits"]);
    
    // The key size that is generated is given by the bits parameter,
    // or 256 bits if no bits parameter is given.
    if (bits == 0)
    {
        bits = 256;
    }

    MXSecretStoragePassphrase *model;
    if (algorithm && iterations && salt)
    {
        model = [MXSecretStoragePassphrase new];
        model.algorithm = algorithm;
        model.iterations = iterations;
        model.salt = salt;
        model.bits = bits;
    }
    
    return model;
}

@end
