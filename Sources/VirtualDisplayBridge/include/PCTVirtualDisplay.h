#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// CGVirtualDisplay（CoreGraphics 私有API）のラッパー。
/// このオブジェクトが生存している間だけ仮想ディスプレイが存在し、
/// 解放（またはプロセス終了）で自動的に消滅する。
@interface PCTVirtualDisplay : NSObject

@property (nonatomic, readonly) CGDirectDisplayID displayID;

/// 指定した実ピクセルサイズのモード群を持つ HiDPI 仮想ディスプレイを作成する。
/// pixelModes: NSValue(size:) の配列（実ピクセル。ポイント解像度はその 1/2）。
/// 失敗時は nil を返す。
- (nullable instancetype)initWithName:(NSString *)name
                           pixelModes:(NSArray<NSValue *> *)pixelModes;

@end

NS_ASSUME_NONNULL_END
