#import <Cocoa/Cocoa.h>

@interface TTTabController : NSObject {
}

- (NSString *)scriptTTY;
- (NSString *)customTitle;
- (Boolean *)scriptBusy;
- (void)setCustomTitle:(NSString *)aTitle;
- (NSColor *)scriptBackgroundColor;
- (void)setScriptBackgroundColor:(NSColor *)aColor;
- (NSURL *)workingDirectoryURL; // 10.7
- (NSURL *)commandWorkingDirectoryURL;// 10.8
- (NSURL *)effectiveWorkingDirectoryURL;
@end


@interface TTWindow : NSWindow {
}

- (NSArray *)tabControllers;
- (void)setSelectedTabController:(TTTabController *)tabController;

@end


@interface TTProfile : NSObject {
}
@end

@interface TTProfileManager : NSObject {
}
+ (TTProfileManager *)sharedProfileManager;
- (TTProfile *)profileWithName:(NSString *)name;
@end


@interface TTWindowController : NSWindowController {
}
- (id)newTab:(id)sender;
- (id)newTabWithProfile:(TTProfile *)profile;
@end
