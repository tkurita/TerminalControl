#include "AEUtils.h"
#import "TerminalInterface.h"
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
#if useLog
	NSLog(@"start TitleForTTYEventHandler");
#endif	
	OSErr resultCode = noErr;
	CFStringRef tty_name = NULL;
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	if (!isTerminalApp()) {
		putMissingValueToReply(reply);
		goto bail;
	}
	
	OSErr err;
	
	tty_name = CFStringCreateWithEvent(ev, keyDirectObject, &err);
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
					putStringToEvent(reply, keyAEResult, (CFStringRef)current_title, kCFStringEncodingUTF8);
					goto bail;
				}
			}
		}
	}
	
	putMissingValueToReply(reply);
	
bail:
	safeRelease(tty_name);
	[pool release];
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
	Boolean is_success = 0;
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	if (!isTerminalApp()) goto bail;
	
	OSErr err;
	tty_name = CFStringCreateWithEvent(ev, kTTYParam, &err);
	if (err != noErr) {
		resultCode = err;
		goto bail;
	}
	new_title = CFStringCreateWithEvent(ev, keyDirectObject, &err);
	if (err != noErr) {
		resultCode = err;
		goto bail;
	}
#if useLog
	CFShow(new_title);
#endif	
	
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
	[pool release];
#if useLog
	printf("end ApplyTitleEventHandler\n");
#endif
	return resultCode;
}

OSErr BGColorForTTYEventHandler(const AppleEvent *ev, AppleEvent *reply, long refcon)
{
#if useLog
	NSLog(@"start BGColorForTTYEventHandler");
#endif
	OSErr resultCode = noErr;
	CFStringRef tty_name = NULL;
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	if (!isTerminalApp()) {
		resultCode = putMissingValueToReply(reply);
		goto bail;
	}
	
	OSErr err;
	tty_name = CFStringCreateWithEvent(ev, keyDirectObject, &err);
	if (!tty_name) {
		resultCode = errAEDescNotFound;
		goto bail;
	}
	
	NSColor *bgcolor;
	NSArray *windows = [NSApp windows];
#if useLog
	NSLog([NSString stringWithFormat:@"Number of windows %d\n", [windows count]]);
#endif
	for (id ttwindow in windows) {
		if ([ttwindow respondsToSelector:@selector(tabControllers)]) {
			NSArray *tabs = [ttwindow tabControllers];
			for (id a_tab in tabs) {
				if ([(NSString *)tty_name isEqualToString:[a_tab scriptTTY]]) {
					bgcolor = [a_tab scriptBackgroundColor];
#if useLog
					NSLog(@"bgcolor : %@", bgcolor);
					NSLog(@"Calibrated : %@", [bgcolor colorUsingColorSpaceName:NSCalibratedRGBColorSpace]);
					NSLog(@"Device Color : %@", [bgcolor colorUsingColorSpaceName:NSDeviceRGBColorSpace]);
#endif					
					CGFloat cclist[4];
					[[bgcolor colorUsingColorSpaceName:NSDeviceRGBColorSpace]
						getRed:&cclist[0] green:&cclist[1] blue:&cclist[2] alpha:&cclist[3]];					
					AEDescList resultList;
					resultCode = AECreateList(NULL, 0, FALSE, &resultList);
					if (resultCode != noErr) {
						NSLog(@"Fail to AECreateList : %d", resultCode);
						goto bail;
					}
					for (short n=0; n < 4; n++) { 
						AEDesc ccdesc;
						long cvalue = cclist[n]*65535;
						err = AECreateDesc(typeSInt32, &cvalue, sizeof(cvalue), &ccdesc);
						if (err != noErr) NSLog(@"Fail to AECreateDesc : %d", err);
						err = AEPutDesc(&resultList, n+1, &ccdesc);
						if (err != noErr) NSLog(@"Fail to AEPutDesc : %d", err);
						AEDisposeDesc(&ccdesc);
					}
					resultCode = AEPutParamDesc(reply, keyAEResult, &resultList);
					AEDisposeDesc(&resultList);
					goto bail;
				}
			}
		}
	}
bail:
	safeRelease(tty_name);
	[pool release];
	return resultCode;
}

CGFloat getColorValue(CFNumberRef num, Boolean is16int)
{
#if useLog
	fprintf(stderr, "Start getColorValue\n");
#endif	
	CGFloat result;
	if (!CFNumberGetValue(num, kCFNumberFloat32Type, &result)) {
		NSLog(@"Failt to CFNumberGetValue");
		return 0;
	}
	if (is16int) result = result/65535;

	return result;
}

OSErr ApplyBackgroundColorEventHandler(const AppleEvent *ev, AppleEvent *reply, long refcon) 
{
#if useLog
	NSLog(@"start ApplyBackgroundColorEventHandler");
#endif
	Boolean is_success = 0;
	OSErr resultCode = noErr;
	CFMutableArrayRef array = NULL;
	CFStringRef tty_name = NULL;
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	if (!isTerminalApp()) goto bail;
	
	OSErr err;
	tty_name = CFStringCreateWithEvent(ev, kTTYParam, &err);
	if (err != noErr ) {
		resultCode = err;
		goto bail;
	}
	
	err = getFloatArray(ev, keyDirectObject, &array);
	if (err != noErr) {
		fprintf(stderr, "Failed to getFloatArray\n");
		resultCode = err;
		goto bail;
	}
	int ccnum = 4;
	
	if (tty_name && array) {
		CFIndex arraylength = CFArrayGetCount(array);
		if (arraylength < 4) ccnum = arraylength;
		
		NSArray *windows = [NSApp windows];
#if useLog
		NSLog([NSString stringWithFormat:@"Number of windows %d\n", [windows count]]);
#endif		
		for (id ttwindow in windows) {
			if ([ttwindow respondsToSelector:@selector(tabControllers)]) {
				NSArray *tabs = [ttwindow tabControllers];
				for (id a_tab in tabs) {
					if ([(NSString *)tty_name isEqualToString:[a_tab scriptTTY]]) {
						NSColor *bgcolor = [a_tab scriptBackgroundColor];
						CGFloat cclist[4];
						[[bgcolor colorUsingColorSpaceName:NSDeviceRGBColorSpace]
						  getRed:&cclist[0] green:&cclist[1] blue:&cclist[2] alpha:&cclist[3]];
						
						for (short n=0; n < ccnum; n++) {
							cclist[n] = getColorValue(CFArrayGetValueAtIndex(array, n), true);
						}
						bgcolor = [NSColor colorWithCalibratedRed:cclist[0] green:cclist[1] 
															 blue:cclist[2] alpha:cclist[3]];		
#if useLog
						NSLog([bgcolor description]);
#endif	
						
						[a_tab setScriptBackgroundColor:bgcolor];
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
	safeRelease(array);
	safeRelease(tty_name);
	[pool release];
#if useLog
	printf("end ApplyTitleEventHandler\n");
#endif
	return resultCode;	
}


