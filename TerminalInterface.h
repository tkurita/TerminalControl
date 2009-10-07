#import <Cocoa/Cocoa.h>

@interface TTWindow : NSWindow {
}

- (NSArray *)tabControllers;

@end

@interface TTTabController : NSObject {
}

- (NSString *)scriptTTY;
- (NSString *)customTitle;
- (void)setCustomTitle:(NSString *)aTitle;
- (NSColor *)scriptBackgroundColor;
- (void)setScriptBackgroundColor:(NSColor *)aColor;

@end
