#include <Carbon/Carbon.h>

OSErr getStringValue(const AppleEvent *ev, AEKeyword theKey, CFStringRef *outStr);
OSErr getFSRef(const AppleEvent *ev, AEKeyword theKey, FSRef *outFSRef);

void showAEDesc(const AppleEvent *ev);
void safeRelease(CFTypeRef theObj);
OSErr putBoolToReply(Boolean aBool, AppleEvent *reply);
OSErr putStringToReply(CFStringRef inStr, CFStringEncoding kEncoding, AppleEvent *reply);
OSErr putMissingValueToReply(AppleEvent *reply);