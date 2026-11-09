#import <Foundation/Foundation.h>
FOUNDATION_EXPORT id magnistra_jsonkit_decode(NSData *data, BOOL mutableContainers,
                                                BOOL allowFragments, NSError **error);
FOUNDATION_EXPORT NSData *magnistra_jsonkit_encode(id object, BOOL prettyPrinted,
                                                   BOOL allowFragments, NSError **error);
