#include "AEUtils.h"
#import "TerminalInterface.h"
#include <Carbon/Carbon.h>
#include <SystemConfiguration/SystemConfiguration.h>

#define useLog 0

#define kTTYParam 'fTTY'
#define kAllowingBusyParam 'awBy'
#define kProcessPatternParam 'prPt'
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

OSErr VersionHandler(const AppleEvent *ev, AppleEvent *reply, SRefCon refcon)
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

Boolean matchProcess(NSRegularExpression *regex, TTTabController *a_tab)
{
    NSString *pname = [[a_tab scriptProcesses] lastObject];
    return [regex numberOfMatchesInString:pname
                                  options:0 range:NSMakeRange(0, [pname length])] > 0;
}

OSErr ActivateTabForDirectoryHandler(const AppleEvent *ev, AppleEvent *reply, long refcon)
{
#if useLog
	NSLog(@"start ActivateTabForDirectory");
#endif	
	OSErr resultCode = noErr;
	CFURLRef url = NULL;
    CFStringRef process_pattern = NULL;
    NSRegularExpression *process_regex = nil;
	TTTabController *target_tab = nil;
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	if (!isTerminalApp()) {
		putMissingValueToReply(reply);
		goto bail;
	}
	
	OSErr err = noErr;
	Boolean allowing_busy = false;
	err = getBoolValue(ev, kAllowingBusyParam, &allowing_busy);
    process_pattern = CFStringCreateWithEvent(ev, kProcessPatternParam, &err);
#if useLog
    NSLog(@"process_pattern : %@", (NSString *)process_pattern);
#endif
    if (process_pattern) {
        process_regex = [NSRegularExpression regularExpressionWithPattern:(NSString *)process_pattern
                                                                  options:0 error:nil];
    }
    
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
				NSURL *wdurl = nil;
				if ([a_tab respondsToSelector:@selector(effectiveWorkingDirectoryURL)]
					&& (wdurl = [a_tab effectiveWorkingDirectoryURL]) ) {
				}else if ([a_tab respondsToSelector:@selector(commandWorkingDirectoryURL)]
						  && (wdurl = [a_tab commandWorkingDirectoryURL])) {
				} else {
					wdurl = [a_tab workingDirectoryURL];
				}
				if (isEqualDir(target_path, local_hostname, wdurl)) {
					if ((![a_tab scriptBusy]) || (allowing_busy && !target_tab)) {
                        if (!process_regex || matchProcess(process_regex ,a_tab)) {
                            target_window = a_ttwindow;
                            target_tab = a_tab;
                            goto bail;
                        }
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
    safeRelease(process_pattern);
	[pool release];
	return resultCode;

}

id TerminalTabForTTY(NSString* ttyname)
{
#if useLog
	NSLog(@"start TerminalTabForTTY : %@", ttyname);
#endif	
	NSArray* windows = [NSApp windows];
	id result = nil;
	for (id ttwindow in windows) {
		if ([ttwindow respondsToSelector:@selector(tabControllers)]) {
			NSArray *tabs = [ttwindow tabControllers];
			for (id a_tab in tabs) {
				if ([ttyname isEqualToString:[a_tab scriptTTY]]) {
					result = a_tab;
					goto bail;
				}
			}
		}
	}
bail:
	return result;
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
	
	OSErr err = noErr;
	tty_name = CFStringCreateWithEvent(ev, keyDirectObject, &err);
	if (err != noErr) {
		resultCode = err;
		goto bail;
	}
	if (!tty_name) {
		resultCode = errAEDescNotFound;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("Fail to obtain new title."), 
						 kCFStringEncodingUTF8);		
		goto bail;
	}
#if useLog
	NSLog(@"wanted tty : %@", tty_name);
#endif	
	id terminal_tab = TerminalTabForTTY((NSString *)tty_name);
#if useLog
	NSLog(@"terminal's tty : %@", [terminal_tab scriptTTY]);
#endif		
	if (!terminal_tab) {
		putMissingValueToReply(reply);
		goto bail;
	}
	NSString *current_title = [terminal_tab customTitle];
#if useLog
	NSLog(@"currernt title : %@", current_title);
#endif
	putStringToEvent(reply, keyAEResult, (CFStringRef)current_title, kCFStringEncodingUTF8);	
bail:
	safeRelease(tty_name);
	[pool release];
#if useLog
	NSLog(@"end of TitleForTTYEventHandler");
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

id TerminalTabForEvent(const AppleEvent* ev, AEKeyword theKey, OSErr *errPtr)
{
	id result = nil;
	AppleEvent new_ev;
	*errPtr = AEDuplicateDesc(ev, &new_ev);
	if (*errPtr != noErr) {
		NSLog(@"Failed to AEDuplicateDesc");
		goto bail;
	}	
	NSAppleEventDescriptor* event_in = [[[NSAppleEventDescriptor alloc] 
										initWithAEDescNoCopy:&new_ev] autorelease];
	
	NSAppleEventDescriptor* target_desc = [event_in paramDescriptorForKeyword:theKey];
	
	if (!target_desc) {
#if useLog
		NSLog(@"No event for expected key."); 
#endif		
		goto bail;
	}
	
	if([target_desc descriptorType] == typeObjectSpecifier) {
		NSScriptObjectSpecifier *tab_specifier = [NSScriptObjectSpecifier 
									objectSpecifierWithDescriptor:target_desc];
		result = [tab_specifier objectsByEvaluatingSpecifier];
		goto bail;
	}
	
	NSString* ttyname = [target_desc stringValue];
	if (!ttyname) goto bail;
	result = TerminalTabForTTY(ttyname);
bail:
	return result;
}


OSErr BGColorOfTermEventHandler(const AppleEvent *ev, AppleEvent *reply, long refcon)
{
#if useLog
	NSLog(@"start BGColorForTTYEventHandler");
#endif
	OSErr resultCode = noErr;
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	if (!isTerminalApp()) {
		resultCode = putMissingValueToReply(reply);
		goto bail;
	}
	
	OSErr err;	
	id a_tab = TerminalTabForEvent(ev, keyDirectObject, &err);
	if (err != noErr) {
		resultCode = err;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("Can't resolve target terminal."), 
						 kCFStringEncodingUTF8);		
		goto bail;
	}
	if (!a_tab) {
		resultCode = errAEWrongDataType;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("Can't resolve target terminal."), 
						 kCFStringEncodingUTF8);		
		goto bail;		
	}
	
	NSColor* bgcolor = [a_tab scriptBackgroundColor];
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
bail:
	[pool release];
	return resultCode;
}

CGFloat getColorValue(CFNumberRef num, Boolean is16int)
{
#if useLog
	NSLog(@"Start getColorValue : %@, %d", num, CFNumberGetType(num));
#endif
	CGFloat result;
#if defined(__LP64__) && __LP64__	
	CFNumberType cg_float_type = kCFNumberFloat64Type;
#else
	CFNumberType cg_float_type = kCFNumberFloat32Type;
#endif
	if (!CFNumberGetValue(num, cg_float_type, &result)) {
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
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	if (!isTerminalApp()) goto bail;
	
	OSErr err;
	id terminal_tab = TerminalTabForEvent(ev, kTTYParam, &err);
	if (err != noErr ) {
		resultCode = err;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("Can't resolve target terminal."), 
						 kCFStringEncodingUTF8);		
		goto bail;
	}
	
	if (!terminal_tab) {
		resultCode = errAEWrongDataType;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("Can't resolve target terminal."), 
						 kCFStringEncodingUTF8);		
		goto bail;		
	}
	
	err = getFloatArray(ev, keyDirectObject, &array);
	if (err != noErr) {
		resultCode = err;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("Can't obtain a color."), 
						 kCFStringEncodingUTF8);		
		goto bail;
	}
	
	if (!array) {
		resultCode = errAEWrongDataType;
		putStringToEvent(reply, keyErrorString, 
						 CFSTR("Can't obtain a color."), 
						 kCFStringEncodingUTF8);		
		goto bail;		
	}
#if useLog
	NSLog(@"passed color : %@", array);
#endif	
	int ccnum = 4;
	
	CFIndex arraylength = CFArrayGetCount(array);
	if (arraylength < 4) ccnum = arraylength;
	NSColor *bgcolor = [terminal_tab scriptBackgroundColor];
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
	
	[terminal_tab setScriptBackgroundColor:bgcolor];
	is_success = 1;	
bail:
	putBoolToReply(is_success, reply);
	safeRelease(array);
	[pool release];
#if useLog
	printf("end ApplyTitleEventHandler\n");
#endif
	return resultCode;	
}


