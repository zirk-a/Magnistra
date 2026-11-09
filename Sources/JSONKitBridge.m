#import "JSONKitBridge.h"
#import "ThirdParty/JSONKit/JSONKit.h"

static NSError *magnistraJSONKitError(NSString *message) {
    return [NSError errorWithDomain:@"MagnistraJSONKit" code:3
                            userInfo:[NSDictionary dictionaryWithObject:message
                                                       forKey:NSLocalizedDescriptionKey]];
}

id magnistra_jsonkit_decode(NSData *input, BOOL mutableContainers,
                             BOOL allowFragments, NSError **error) {
    if (input == nil) {
        if (error != NULL) *error = magnistraJSONKitError(@"Missing JSON data");
        return nil;
    }
    NSData *source = input;
    if (allowFragments) {
        NSMutableData *wrapped = [NSMutableData dataWithBytes:"[" length:1];
        [wrapped appendData:input];
        [wrapped appendBytes:"]" length:1];
        source = wrapped;
    }
    id value = mutableContainers
        ? [source mutableObjectFromJSONDataWithParseOptions:JKParseOptionStrict error:error]
        : [source objectFromJSONDataWithParseOptions:JKParseOptionStrict error:error];
    if (!allowFragments || value == nil) return value;
    if ([value isKindOfClass:[NSArray class]] && [value count] == 1)
        return [value objectAtIndex:0];
    if (error != NULL) *error = magnistraJSONKitError(@"Malformed JSON fragment");
    return nil;
}

NSData *magnistra_jsonkit_encode(id object, BOOL prettyPrinted,
                                 BOOL allowFragments, NSError **error) {
    JKSerializeOptionFlags flags = prettyPrinted ? JKSerializeOptionPretty : JKSerializeOptionNone;
    if ([object isKindOfClass:[NSDictionary class]])
        return [(NSDictionary *)object JSONDataWithOptions:flags error:error];
    if ([object isKindOfClass:[NSArray class]])
        return [(NSArray *)object JSONDataWithOptions:flags error:error];
    if (allowFragments) {
        NSArray *wrapped = [NSArray arrayWithObject:object];
        NSData *encoded = [wrapped JSONDataWithOptions:flags error:error];
        if (encoded == nil || [encoded length] < 2) return nil;
        return [encoded subdataWithRange:NSMakeRange(1, [encoded length] - 2)];
    }
    if (error != NULL) *error = magnistraJSONKitError(@"Expected JSON object or array");
    return nil;
}
