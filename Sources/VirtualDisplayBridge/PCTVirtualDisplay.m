#import "PCTVirtualDisplay.h"

// ---- CoreGraphics 私有クラスの宣言（ヘッダ非公開のため自前定義） ----

@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic, strong) NSArray *modes;
@property (nonatomic) unsigned int hiDPI;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy) void (^terminationHandler)(id, id);
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplay : NSObject
@property (nonatomic, readonly) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

// ---- ラッパー実装 ----

@implementation PCTVirtualDisplay {
    CGVirtualDisplay *_display;
}

- (nullable instancetype)initWithName:(NSString *)name
                           pixelModes:(NSArray<NSValue *> *)pixelModes {
    self = [super init];
    if (!self) return nil;
    if (!NSClassFromString(@"CGVirtualDisplay") || pixelModes.count == 0) return nil;

    unsigned int maxW = 0, maxH = 0;
    NSMutableArray *modes = [NSMutableArray arrayWithCapacity:pixelModes.count];
    for (NSValue *value in pixelModes) {
        CGSize size = value.sizeValue;
        maxW = MAX(maxW, (unsigned int)size.width);
        maxH = MAX(maxH, (unsigned int)size.height);
        [modes addObject:[[CGVirtualDisplayMode alloc] initWithWidth:(unsigned int)size.width
                                                              height:(unsigned int)size.height
                                                         refreshRate:60]];
    }

    CGVirtualDisplayDescriptor *desc = [CGVirtualDisplayDescriptor new];
    desc.name = name;
    desc.maxPixelsWide = maxW;
    desc.maxPixelsHigh = maxH;
    desc.sizeInMillimeters = CGSizeMake(maxW / 10.0, maxH / 10.0);
    desc.productID = 0x7C05;
    desc.vendorID = 0x7C05;
    desc.serialNum = 1;
    desc.queue = dispatch_get_main_queue();
    desc.terminationHandler = ^(id sender, id info) {};

    _display = [[CGVirtualDisplay alloc] initWithDescriptor:desc];
    if (!_display) return nil;

    CGVirtualDisplaySettings *settings = [CGVirtualDisplaySettings new];
    settings.hiDPI = 1;
    settings.modes = modes;
    if (![_display applySettings:settings]) return nil;

    _displayID = _display.displayID;
    return self;
}

@end
