#include "AEUtils.h"

#include <Carbon/Carbon.h>

#define useLog 0

#define kTTYParam 'fTTY'

int isTerminalApp()
{
	CFBundleRef main_bundle = CFBundleGetMainBundle();
	CFStringRef app_identifier = CFBundleGetIdentifier(main_bundle);
	
	CFComparisonResult cresult = CFStringCompare(app_identifier, CFSTR("com.apple.Terminal"), 0);
#if useLog
	CFShow(app_identifier);
#endif
	return (cresult == kCFCompareEqualTo);
}

OSErr TitleForTTYEventHandler(const AppleEvent *ev, AppleEvent *reply, long refcon)
{
	OSErr resultCode = noErr;
	CFStringRef tty_name = NULL;	
	
	if (!isTerminalApp()) {
		putMissingValueToReply(reply);
		return resultCode;
	}
	
	OSErr err;
	
	err = getStringValue(ev, keyDirectObject, &tty_name);
	if (!tty_name) {
		resultCode = errAEDescNotFound;
		goto bail;
	}
	
	NSArray *windows = [NSApp windows];
#if useLog
	NSLog([NSString stringWithFormat:@"Number of windows %d\n", [windows count]]);
#endif
	NSString *current_title = nil;
	for (id ttwindow in windows) {
		if ([ttwindow respondsToSelector:@selector(tabControllers)]) {
			NSArray *tabs = [ttwindow tabControllers];
			for (id a_tab in tabs) {
				if ([(NSString *)tty_name isEqualToString:[a_tab scriptTTY]]) {
					current_title = [a_tab customTitle];
#if useLog
					NSLog([a_tab scriptTTY]);
#endif	
					putStringToReply((CFStringRef)current_title, kCFStringEncodingUTF8, reply);
					goto bail;
				}
			}
		}
	}
	
	putMissingValueToReply(reply);
	
bail:
	safeRelease(tty_name);

#if useLog
	printf("current title\n");
	CFShow(current_title);
	printf("end titleForTTYEventHandler\n");
#endif
	
	return resultCode;	
}

OSErr ApplyTitleEventHandler(const AppleEvent *ev, AppleEvent *reply, long refcon)
{
#if useLog
	printf("start ApplyTitleEventHandler\n	");
#endif	
	
	OSErr resultCode = noErr;
	CFStringRef new_title = NULL;
	CFStringRef tty_name = NULL;	
	
	if (!isTerminalApp()) goto bail;
	
	OSErr err;
	err = getStringValue(ev, kTTYParam, &tty_name);	
	err = getStringValue(ev, keyDirectObject, &new_title);
#if useLog
	CFShow(new_title);
#endif	
	Boolean is_success = 0;
	if (tty_name && new_title) {
		NSArray *windows = [NSApp windows];
#if useLog
		NSLog([NSString stringWithFormat:@"Number of windows %d\n", [windows count]]);
#endif		
		for (id ttwindow in windows) {
			if ([ttwindow respondsToSelector:@selector(tabControllers)]) {
				NSArray *tabs = [ttwindow tabControllers];
				for (id a_tab in tabs) {
					if ([(NSString *)tty_name isEqualToString:[a_tab scriptTTY]]) {
						[a_tab setCustomTitle:(NSString *)new_title];
						is_success = 1;
						goto bail;
					}
				}
			}
		}
	} else {
		resultCode = errAEDescNotFound;
	}
	
bail:
	putBoolToReply(is_success, reply);
	safeRelease(new_title);
	safeRelease(tty_name);
	
#if useLog
	printf("end ApplyTitleEventHandler\n");
#endif
	return resultCode;
}

