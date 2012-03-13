#include "AEUtils.h"
#import "TerminalInterface.h"
#include <Carbon/Carbon.h>
#include <SystemConfiguration/SystemConfiguration.h>

#define useLog 0

#define kTTYParam 'fTTY'
#define kAllowingBusyParam 'awBy'
#define kInWindowParam 'kfil'
#define kToTabParam 'tTab'
#define BUNDLE_ID CFSTR("Scriptfactory.osax.TerminalControl")

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

OSErr versionHandler(const AppleEvent *ev, AppleEvent *reply, SRefCon refcon)
{
#if useLog
	fprintf(stderr, "start versionHandler\n");
#endif			
	OSErr err;
	CFBundleRef	bundle = CFBundleGetBundleWithIdentifier(BUNDLE_ID);
	CFDictionaryRef info = CFBundleGetInfoDictionary(bundle);
	
	CFStringRef vers = CFDictionaryGetValue(info, CFSTR("CFBundleShortVersionString"));
	err = putStringToEvent(reply, keyAEResult, vers, kCFStringEncodingUnicode);
	return err;
}

OSErr MakeTabInHandler(const AppleEvent *ev, AppleEvent *reply, long refcon)
{
	OSErr resultCode = noErr;
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	if (!isTerminalApp()) {
		putMissingValueToReply(reply);
		goto bail;
	}
	OSErr err = noErr;
	AppleEvent new_ev;
	err = AEDuplicateDesc(ev,&new_ev);
	if (err != noErr) {
		resultCode = err;
		fprintf(stderr, "Failed to AEDuplicateDesc : %d\n", err);
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("Failed to AEDuplicateDesc."), kCFStringEncodingUTF8);
		goto bail;
	}
	NSAppleEventDescriptor *event_in = [[[NSAppleEventDescriptor alloc] 
											initWithAEDescNoCopy:&new_ev] autorelease];
	NSAppleEventDescriptor *window_desc = [event_in paramDescriptorForKeyword:kInWindowParam];
	NSAppleEventDescriptor *profile_desc = [event_in paramDescriptorForKeyword:keyDirectObject];

	if (!window_desc) {
		resultCode = errAEParamMissed;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("No 'in' parameter. A reference to a window must be passed as the 'in' parameter."), 
						 kCFStringEncodingUTF8);
		goto bail;
	} else if ([window_desc descriptorType] != typeObjectSpecifier) {
		resultCode = errAEWrongDataType;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("'in' parameter is no an object specifier. A reference to a window must be passed as the 'in' parameter."), 
						 kCFStringEncodingUTF8);
		goto bail;		
	}
	
	NSScriptObjectSpecifier *window_specifier = [NSScriptObjectSpecifier 
												 objectSpecifierWithDescriptor:window_desc];
	
	TTWindow *a_ttwindow = [window_specifier objectsByEvaluatingSpecifier];
	if (!a_ttwindow || ![a_ttwindow isKindOfClass:NSClassFromString(@"TTWindow")]) {
		resultCode = errAEWrongDataType;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("'in' parametr is invalid value."), 
						 kCFStringEncodingUTF8);
		goto bail;				
	}
	
	id new_tab = nil;
	if (profile_desc) {
		TTProfile *profile = [[NSClassFromString(@"TTProfileManager") sharedProfileManager] 
									  profileWithName:[profile_desc stringValue]];
		if (!profile) {
			putStringToEvent(reply, keyErrorString, 
							 CFStringCreateWithFormat (kCFAllocatorDefault, 
													   NULL ,CFSTR("Can't find profile \"%@\""),
													   (CFStringRef)[profile_desc stringValue]),
														kCFStringEncodingUTF8);
			goto bail;
		}
		new_tab = [[a_ttwindow windowController] newTabWithProfile:profile];
	} else {
		new_tab = [[a_ttwindow windowController] newTab:nil];
	}
	
	NSScriptObjectSpecifier *tab_specifier = [new_tab objectSpecifier];
	NSAppleEventDescriptor *tab_desc = [tab_specifier descriptor];
	
	err = AEPutParamDesc(reply, keyAEResult, [tab_desc aeDesc]);
							 
bail:
	[pool release];
	return resultCode;
}

Boolean isEqualDir(NSString *targetPath, NSString *localHostName, NSURL *url)
{
	NSString *host = [url host];
#if useLog
	NSLog(@"Host :%@", host);
#endif	
	if ([host isEqualToString:localHostName] || [host isEqualToString:@"localhost"]) {
		return [targetPath isEqualToString:[url path]];
	}
	return false;
}

OSErr ActivateTabForDirectoryHandler(const AppleEvent *ev, AppleEvent *reply, long refcon)
{
#if useLog
	NSLog(@"start ActivateTabForDirectory");
#endif	
	OSErr resultCode = noErr;
	CFURLRef url = NULL;
	TTTabController *target_tab = nil;
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	if (!isTerminalApp()) {
		putMissingValueToReply(reply);
		goto bail;
	}
	
	OSErr err;
	Boolean allowing_busy = false;
	err = getBoolValue(ev, kAllowingBusyParam, &allowing_busy);
	
	url = CFURLCreateWithEvent(ev, keyDirectObject, &err);
# if useLog
	NSLog(@"%@", (NSURL *)url);
#endif
	if (!url) {
		resultCode = err;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("No valid file reference."), 
						 kCFStringEncodingUTF8);		
		goto bail;
	}
	NSString *target_path = [(NSURL *)url path];
	NSString *local_hostname = [(NSString *)SCDynamicStoreCopyLocalHostName(NULL)
									stringByAppendingString:@".local"] ;
	NSArray *windows = [NSApp windows];
	TTWindow *target_window = nil;
	for (TTWindow *a_ttwindow in windows) {
		if ([a_ttwindow respondsToSelector:@selector(tabControllers)]) {
			NSArray *tabs = [a_ttwindow tabControllers];
			for (id a_tab in tabs) {
				if (isEqualDir(target_path, local_hostname, [a_tab workingDirectoryURL])) {
					if (![a_tab scriptBusy]) {
						target_window = a_ttwindow;
						target_tab = a_tab;
						goto bail;
					} else if (allowing_busy && !target_tab) {
						target_window = a_ttwindow;
						target_tab = a_tab;						
					}
				}
			}
		}
	}
	
bail:
	if (target_tab) {
		[target_window setSelectedTabController:target_tab];
		[target_window makeKeyAndOrderFront:nil];
		NSScriptObjectSpecifier *tab_specifier = [target_tab objectSpecifier];
		NSAppleEventDescriptor *tab_desc = [tab_specifier descriptor];
		resultCode = AEPutParamDesc(reply, keyAEResult, [tab_desc aeDesc]);
	} else {
		err = putMissingValueToReply(reply);
	}

	safeRelease(url);
	[pool release];
	return resultCode;

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
	NSLog(@"Number of windows : %d", [windows count]);
#endif
	NSString *current_title = nil;
	for (id ttwindow in windows) {
		if ([ttwindow respondsToSelector:@selector(tabControllers)]) {
			NSArray *tabs = [ttwindow tabControllers];
			for (id a_tab in tabs) {
				if ([(NSString *)tty_name isEqualToString:[a_tab scriptTTY]]) {
					current_title = [a_tab customTitle];
#if useLog
					NSLog(@"tty : %@", [a_tab scriptTTY]);
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
	NSString *new_title = nil;
	NSString *tty_name = nil;	
	Boolean is_success = 0;
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	if (!isTerminalApp()) goto bail;
	
	OSErr err;
	
	AppleEvent new_ev;
	err = AEDuplicateDesc(ev,&new_ev);
	if (err != noErr) {
		resultCode = err;
		fprintf(stderr, "Failed to AEDuplicateDesc : %d\n", err);
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("Failed to AEDuplicateDesc."), kCFStringEncodingUTF8);
		goto bail;
	}
	NSAppleEventDescriptor *event_in = [[[NSAppleEventDescriptor alloc] 
										 initWithAEDescNoCopy:&new_ev] autorelease];
	new_title = [[event_in paramDescriptorForKeyword:keyDirectObject] stringValue];
	if (!new_title) {
		resultCode = errAEParamMissed;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("No vaild title."), 
						 kCFStringEncodingUTF8);
		goto bail;
	}
	NSAppleEventDescriptor *tab_desc = [event_in paramDescriptorForKeyword:kToTabParam];
	if (tab_desc) {
		if ([tab_desc descriptorType] != typeObjectSpecifier) {
			resultCode = errAENotAnObjSpec;
			putStringToEvent(reply, keyErrorString, 
							 CFSTR("The terminal tab specifier is invalid."), 
							 kCFStringEncodingUTF8);
			goto bail;	
		}
		NSScriptObjectSpecifier *tab_specifier = [NSScriptObjectSpecifier 
												objectSpecifierWithDescriptor:tab_desc];
		id a_tab = [tab_specifier objectsByEvaluatingSpecifier];
		if ([a_tab respondsToSelector:@selector(setCustomTitle:)]) {
			[a_tab setCustomTitle:new_title];
			is_success = 1;
		} else {
			resultCode = errAEWrongDataType;
			putStringToEvent(reply, keyErrorString, 
							 CFSTR("Can't set custom title."), 
							 kCFStringEncodingUTF8);
			goto bail;
		}		
	} else {
		NSAppleEventDescriptor *tty_desc = [event_in paramDescriptorForKeyword:kTTYParam];
		if (!tty_desc) {
			resultCode = errAEDescNotFound;
			putStringToEvent(reply, keyErrorString, 
							 CFSTR("No valid tarminal specifier."), 
							 kCFStringEncodingUTF8);
			goto bail;	
			
		}
		tty_name = [tty_desc stringValue];	
		NSArray *windows = [NSApp orderedWindows];
#if useLog
		NSLog(@"Number of windows : %d", [windows count]);
#endif		
		for (id ttwindow in windows) {
			if ([ttwindow respondsToSelector:@selector(tabControllers)]) {
				NSArray *tabs = [ttwindow tabControllers];
				for (id a_tab in tabs) {
					if ([(NSString *)tty_name isEqualToString:[a_tab scriptTTY]]) {
						[a_tab setCustomTitle:new_title];
						is_success = 1;
						goto bail;
					}
				}
			}
		}
	} 
	
bail:
	putBoolToReply(is_success, reply);
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
	NSLog(@"Number of windows : %d", [windows count]);
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
		NSLog(@"Number of windows : %d", [windows count]);
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
						NSLog(@"%@", [bgcolor description]);
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


