#include "AEUtils.h"
#include <sys/param.h>
#define bufferSize MAXPATHLEN+1 	

#define useLog 0

void showAEDesc(const AppleEvent *ev)
{
	Handle result;
	OSStatus resultStatus;
	resultStatus = AEPrintDescToHandle(ev,&result);
	printf("%s\n",*result);
	DisposeHandle(result);
}

void safeRelease(CFTypeRef theObj)
{
	if (theObj != NULL) {
		CFRelease(theObj);
	}
}

OSErr getURLFromUTextDesc(const AEDesc *utdesc_p, CFURLRef *urlRef_p)
{
	OSErr err;
	Size theLength = AEGetDescDataSize(utdesc_p);
	
	UInt8 *theData = malloc(theLength);
	err = AEGetDescData(utdesc_p, theData, theLength);
	if (err != noErr) goto bail;
	
	CFStringRef pathStr = CFStringCreateWithBytes(NULL, theData, theLength, kCFStringEncodingUnicode, false);
	
	CFURLPathStyle pathStyle;
	if (CFStringHasPrefix(pathStr, CFSTR("/"))) {
		pathStyle = kCFURLPOSIXPathStyle;
	}
	else {
		pathStyle = kCFURLHFSPathStyle;
	}	
	*urlRef_p = CFURLCreateWithFileSystemPath(NULL, pathStr, pathStyle, true);
	CFRelease(pathStr);
	
bail:
	free(theData);
	return err;
}

OSStatus getFSRefFromUTextAE(const AppleEvent *ev, AEKeyword theKey, FSRef *ref_p)
{
	AEDesc givenDesc;
	OSStatus err = AEGetParamDesc(ev, theKey, typeUnicodeText, &givenDesc);
#if useLog
	showAEDesc(&givenDesc);
#endif
	if (err != noErr) goto bail;
	
	CFURLRef urlRef = NULL;
	err = getURLFromUTextDesc(&givenDesc, &urlRef);
	if (err != noErr) goto bail;
	
	Boolean canGetFSRef = 0;
	if (urlRef != NULL) {
		canGetFSRef = CFURLGetFSRef(urlRef, ref_p);
	}
	
	if (! canGetFSRef) {
		err = errAECoercionFail;
	}

bail:
	safeRelease(urlRef);
	return err;
}

OSStatus getFSRefFromAE(const AppleEvent *ev, AEKeyword theKey, FSRef *ref_p)
{
	AEDesc givenDesc;
	OSStatus err = AEGetParamDesc(ev, keyDirectObject, typeFSRef, &givenDesc);
#if useLog
	showAEDesc(&givenDesc);
#endif
	err = AEGetDescData(&givenDesc, ref_p, sizeof(FSRef));
	return err;
}

OSErr getFSRef(const AppleEvent *ev, AEKeyword theKey, FSRef *outFSRef_p)
{
	OSErr err = noErr;		
	DescType typeCode;
	Size dataSize;
	err = AESizeOfParam(ev, keyDirectObject, &typeCode, &dataSize);
	
	if (err != noErr) goto bail;
	
	switch (typeCode) {
		case typeAlias:
#if !__LP64__			
		case typeFSS:
#endif
		case typeFileURL:
		case cObjectSpecifier:
			err = getFSRefFromAE(ev, theKey, outFSRef_p);
			break;
		case typeChar:
		case typeUTF8Text:
		case typeUnicodeText:
			err = getFSRefFromUTextAE(ev, theKey, outFSRef_p);
			break;
		default:
			err = errAEWrongDataType;
	}

bail:	
	return err;
}

CFNumberType CFNumberTypeWithAENumberType(DescType typeCode)
{
	CFNumberType result = 0;
	switch (typeCode) {
		case typeSInt16:
			result = kCFNumberSInt16Type;
			break;
		case typeSInt32:
			result = kCFNumberSInt32Type;
			break;
		case typeSInt64:
			result = kCFNumberSInt64Type;
			break;
		case typeIEEE32BitFloatingPoint:
			result =  kCFNumberFloat32Type;
			break;
		case typeIEEE64BitFloatingPoint:
			result = kCFNumberFloat64Type;
			break;
		default:
			break;
	}
	return result;
}

OSErr getFloatArray(const AppleEvent *ev, AEKeyword theKey,  CFMutableArrayRef *outArray)
{
	OSErr err;
	DescType typeCode;
	Size dataSize;
	
	err = AESizeOfParam(ev, theKey, &typeCode, &dataSize);
	if ((err != noErr) || (typeCode == typeNull)){
		goto bail;
	}

	AEDescList  aeList;
	err = AEGetParamDesc(ev, theKey, typeAEList, &aeList);
	if (err != noErr) goto bail;
	
    long        count = 0;
	err = AECountItems(&aeList, &count);
	if (err != noErr) goto bail;
	
	
	*outArray = CFArrayCreateMutable(NULL, 0, NULL);
	
    for(long index = 1; index <= count; index++) {
		float value;
		err = AEGetNthPtr(&aeList, index, typeIEEE32BitFloatingPoint,
						  NULL, NULL, &value,
						  sizeof(value), NULL);
		if (err != noErr) {
			fprintf(stderr, "Fail to AEGetNthPtr in getFloatArray\n");
			goto bail;
		}
		CFNumberRef cfnum = CFNumberCreate(NULL, kCFNumberFloat32Type, &value);
		CFArrayAppendValue(*outArray, cfnum);
		//CFRelease(cfnum); // this statement cause error. I can't understand the reason.
    }
bail:
#if useLog
	CFShow(*outArray);
	fprintf(stderr, "end of getFloatArray\n");
#endif	
	return err;
}

OSErr getStringValue(const AppleEvent *ev, AEKeyword theKey, CFStringRef *outStr)
{
#if useLog
	printf("start getStringValue\n");
#endif
	OSErr err;
	DescType typeCode;
	DescType returnedType;
    Size actualSize;
	Size dataSize;
	CFStringEncoding encodeKey;
	OSType a_type;
	
	err = AESizeOfParam(ev, theKey, &typeCode, &dataSize);
	if ((err != noErr) || (typeCode == typeNull)){
		goto bail;
	}
	
	if (dataSize == 0) {
		*outStr = CFSTR("");
		goto bail;
	}
	
	switch (typeCode) {
		case typeChar:
			encodeKey = CFStringGetSystemEncoding();
			break;
		case typeUTF8Text:
			encodeKey = kCFStringEncodingUTF8;
			break;
		case typeType:
			err = AEGetParamPtr (ev, theKey, typeCode, &returnedType, &a_type, dataSize, &actualSize);
			if (a_type == cMissingValue) {
				goto bail;
			}
			//break;
		default :
			typeCode = typeUnicodeText;
			encodeKey = kCFStringEncodingUnicode;
	}
	
	UInt8 *dataPtr = malloc(dataSize);
	err = AEGetParamPtr (ev, theKey, typeCode, &returnedType, dataPtr, dataSize, &actualSize);
	if (actualSize > dataSize) {
#if useLog
		printf("buffere size is allocated. data:%i actual:%i\n", dataSize, actualSize);
#endif	
		dataSize = actualSize;
		dataPtr = (UInt8 *)realloc(dataPtr, dataSize);
		if (dataPtr == NULL) {
			printf("fail to reallocate memory\n");
			goto bail;
		}
		err = AEGetParamPtr (ev, theKey, typeCode, &returnedType, dataPtr, dataSize, &actualSize);
	}
	
	if (err != noErr) {
		free(dataPtr);
		goto bail;
	}
	
	*outStr = CFStringCreateWithBytes(NULL, dataPtr, dataSize, encodeKey, false);
	free(dataPtr);
bail:
#if useLog		
	printf("end getStringValue\n");
#endif
	return err;
}

OSErr putStringToReply(CFStringRef inStr, CFStringEncoding kEncoding, AppleEvent *reply)
{
// kEncoding can be omitted to specify with giving NULL
#if useLog
	printf("start putStringToReply\n");
#endif
	OSErr err;
	DescType resultType;
	
	switch (kEncoding) {
		case kCFStringEncodingUTF8 :
			resultType = typeUTF8Text;
			break;
		default :
			resultType = typeUnicodeText;
	}
	
	const char *constBuff = CFStringGetCStringPtr(inStr, kEncoding);
	
	AEDesc resultDesc;
	if (constBuff == NULL) {
		char *buffer;
		CFIndex charLen = CFStringGetLength(inStr);
		CFIndex maxLen = CFStringGetMaximumSizeForEncoding(charLen, kEncoding);
		buffer = malloc(maxLen+1);
		CFStringGetCString(inStr, buffer, maxLen+1, kEncoding);
		err=AECreateDesc(resultType, buffer, strlen(buffer), &resultDesc);
		free(buffer);
	}
	else {
		err=AECreateDesc(resultType, constBuff, strlen(constBuff), &resultDesc);
	}
	
	
	if (err != noErr) goto bail;
	
	err=AEPutParamDesc(reply, keyAEResult, &resultDesc);
	if (err != noErr) {
		AEDisposeDesc(&resultDesc);
	}
	
bail:
#if useLog
	printf("end putStringToReply\n");
#endif
	return err;
}

OSErr putBoolToReply(Boolean aBool, AppleEvent *reply)
{
#if useLog
	printf("start putBoolToReply\n");
#endif
	OSErr err;
	DescType resultType = (aBool? typeTrue:typeFalse);
	AEDesc resultDesc;
	err=AECreateDesc(resultType, NULL, 0, &resultDesc);
	err=AEPutParamDesc(reply, keyAEResult, &resultDesc);
	
#if useLog
	printf("end putBoolToReply\n");
#endif
	return err;
}

OSErr putMissingValueToReply(AppleEvent *reply)
{
	OSErr err;
	DescType resultType = 'msng';
	AEDesc resultDesc;
	err=AECreateDesc(resultType, NULL, 0, &resultDesc);
	err=AEPutParamDesc(reply, keyAEResult, &resultDesc);
	return err;
}

OSErr putFilePathToReply(CFURLRef inURL, AppleEvent *reply)
{	
	OSErr err;
	char buffer[bufferSize];
	CFURLGetFileSystemRepresentation(inURL, true, (UInt8 *)buffer, bufferSize);
	
	AEDesc resultDesc;

	err=AECreateDesc(typeUTF8Text, buffer, strlen(buffer), &resultDesc);
	
	
	if (err != noErr) goto bail;
	
	err=AEPutParamDesc(reply, keyAEResult, &resultDesc);
	if (err != noErr) {
		AEDisposeDesc(&resultDesc);
	}
	
bail:
		return err;
}