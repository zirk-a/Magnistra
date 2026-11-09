#import <Foundation/Foundation.h>

float MNoIntrinsicMetric = -1.0f;

@interface MDataAsset : NSObject
- (id)initWithName:(NSString *)name bundle:(NSBundle *)bundle;
@end

@implementation MDataAsset

- (id)initWithName:(NSString *)name bundle:(NSBundle *)bundle
{
    Class realClass = NSClassFromString(@"NSDataAsset");

    if (realClass == Nil) {
        [self release];
        return nil;
    }

    id allocated = [realClass alloc];
    id replacement = [allocated
        performSelector:@selector(initWithName:bundle:)
        withObject:name
        withObject:bundle];

    [self release];
    return replacement;
}

@end
