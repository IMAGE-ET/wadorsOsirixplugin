/*
 Copyright: (c) Mega LTD & Jesros SA, Uruguay
 Authors:   jacques.fauquex@mega.com.uy & cl.baeza@gmail.com
 
 All Rights Reserved.
 
 Source code and binaries are subject to the terms of the Mozilla Public License, v. 2.0.
 If a copy of the MPL was not distributed with this file, You can obtain one at
 http://mozilla.org/MPL/2.0/
 
 Covered Software is provided under this License on an “as is” basis, without warranty of
 any kind, either expressed, implied, or statutory, including, without limitation,
 warranties that the Covered Software is free of defects, merchantable, fit for a particular
 purpose or non-infringing. The entire risk as to the quality and performance of the Covered
 Software is with You. Should any Covered Software prove defective in any respect, You (not
 any Contributor) assume the cost of any necessary servicing, repair, or correction. This
 disclaimer of warranty constitutes an essential part of this License. No use of any Covered
 Software is authorized under this License except under this disclaimer.
 
 Under no circumstances and under no legal theory, whether tort (including negligence),
 contract, or otherwise, shall any Contributor, or anyone who distributes Covered Software
 as permitted above, be liable to You for any direct, indirect, special, incidental, or
 consequential damages of any character including, without limitation, damages for lost
 profits, loss of goodwill, work stoppage, computer failure or malfunction, or any and all
 other commercial damages or losses, even if such party shall have been informed of the
 possibility of such damages. This limitation of liability shall not apply to liability for
 death or personal injury resulting from such party’s negligence to the extent applicable
 law prohibits such limitation. Some jurisdictions do not allow the exclusion or limitation
 of incidental or consequential damages, so this exclusion and limitation may not apply to
 You.
 */


#import "wadoQueue.h"
#import <OsiriXAPI/DicomDatabase.h>

static wadoQueue *sharedWadoQueue = nil;
static NSMutableArray *urls;
static NSString *incomingPath;
static NSData *dicomPreambleData;
static NSData *pkSignatureData;


static NSArray *imageRMT;
static NSArray *videoRMT;
static NSArray *textRMT;
static NSArray *dicomMT;
static NSArray *buMT;//uncompressed bulkdata
static NSArray *bcMT;//compressed bulkdata

static NSData *hh;
static NSData *rn;
static NSData *rnrn;

static NSTimeInterval requestStart;
static NSTimeInterval timeout;

@implementation wadoQueue

#pragma mark singleton
+(wadoQueue*)queue
{
    if (sharedWadoQueue == nil) return [wadoQueue queueUrlSet:nil];
    return sharedWadoQueue;
}

+(wadoQueue*)queueUrlSet:(NSSet*)urlSet;
{
    if (sharedWadoQueue == nil)
    {
        sharedWadoQueue = [[super allocWithZone:NULL] init];
        urls=[[NSMutableArray array]retain];
        incomingPath=[[[DicomDatabase activeLocalDatabase] incomingDirPath]retain];
        
        UInt32 dicmSignature=0x4D434944;//DICM
        NSMutableData *first132=[NSMutableData dataWithLength:128];
        [first132 appendData:[NSData dataWithBytes:&dicmSignature length:4]];
        dicomPreambleData =[[NSData alloc]initWithData:first132];

        uint16 pk=0x1234;
        pkSignatureData=[[NSData alloc]initWithBytes:&pk length:2];
        
        imageRMT=[@[
                   @"image/jpeg",
                   @"image/gif",
                   @"image/png",
                   @"image/jp2"
                   ]retain];
        videoRMT=[@[
                   @"video/mpeg",
                   @"video/mp4",
                   @"video/jpeg",
                  ]retain];
        textRMT=[@[
                   @"text/html",
                   @"text/plain",
                   @"text/xml",
                   @"text/rtf",
                   @"application/pdf"
                   ]retain];//CDA returned as text/xml
        dicomMT=[@[
                  @"application/dicom",
                  @"application/dicom+xml",
                  @"application/dicom+json"
                 ]retain];
        buMT=[@[
               @"application/octet-stream"
              ]retain];
        bcMT=[@[
               @"image/*",
               @"video/*"
               ]retain];

        hh = [[@"--" dataUsingEncoding:NSASCIIStringEncoding]retain];
        rn = [[@"\r\n" dataUsingEncoding:NSASCIIStringEncoding]retain];
        rnrn = [[@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding]retain];
        
        requestStart=0;
        timeout=[[NSUserDefaults standardUserDefaults] floatForKey: @"WADOTimeout"];
        if( timeout < 240) timeout = 240;
        [self performSelectorOnMainThread: @selector(startLooping:) withObject:sharedWadoQueue waitUntilDone:NO];
    }
    if (urlSet)
    {
        for (id object in urlSet)
        {
            if ([object isKindOfClass:[NSURL class]])
            {
                if ([urls indexOfObject:(NSURL*)object]==NSNotFound)
                    [urls addObject:[[NSURL alloc]initWithString:((NSURL*)object).absoluteString]];
            }
        }
    }
    return sharedWadoQueue;
}

+(void)startLooping:(id)sharedWadoQueue
{
    [NSTimer scheduledTimerWithTimeInterval:1 target:sharedWadoQueue selector:@selector(nextHTTPRequest) userInfo:nil repeats:YES];
}

+ (id)allocWithZone:(NSZone *)zone
{
    return [[self queue] retain];
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (id)retain
{
    return self;
}

- (NSUInteger)retainCount
{
    return NSUIntegerMax;  //denotes an object that cannot be released
}

- (oneway void)release
{
    //do nothing
}


- (id)autorelease
{
    return self;
}


#pragma mark business logics

-(void)nextHTTPRequest
{
    //NSLog(@"hola");
    //requestStart keeps the time of the request start until the request is completed, then it goes back to nill value. We use it to avoid more than a request at a time
    if ((requestStart==0) || ([[NSDate date]timeIntervalSinceReferenceDate] > requestStart+timeout))
    {
        if ([urls count])requestStart=[[NSDate date]timeIntervalSinceReferenceDate];
        else requestStart=0;
        
        while ([urls count] && ([[NSDate date]timeIntervalSinceReferenceDate] < requestStart+timeout))
        {
            NSURL *currentURL=[[NSURL alloc]initWithString:((NSURL*)[urls objectAtIndex:0]).absoluteString];
            [urls removeObjectAtIndex:0];
            BOOL wadoURI=[currentURL.query hasPrefix:@"requestType=WADO"];
            //NSLog(@"%@",currentURL);

            //request, response and error
            NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:currentURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:timeout];
            [request setHTTPMethod:@"GET"];
            if (!wadoURI) [request setValue:@"multipart/related;type=application/dicom" forHTTPHeaderField:@"Accept"];
            NSHTTPURLResponse *response=nil;
            //URL properties: expectedContentLength, MIMEType, textEncodingName
            //HTTP properties: statusCode, allHeaderFields
            NSError *error=nil;

            
            NSData *data=[NSURLConnection sendSynchronousRequest:request
                                               returningResponse:&response
                                                           error:&error];
            if (error)
            {
                NSLog(@"ERROR %@\r\n%@",currentURL.absoluteString,[error description]);
                break;
            }
            switch (response.statusCode)
            {
                    
                case 406:NSLog(@"406-NotAcceptable: %@",currentURL.absoluteString);
                    break;
#pragma mark 200
                case 200://NSLog(@"200-OK");
                    if (wadoURI)
                    {
                        if( [data length] > 2)
                        {
                            NSLog(@"ERROR data shorter than 2 bytes: %@",currentURL.absoluteString);
                            break;
                        }
                        //compressed?
                        uint16 firstTwoChar;
                        [data getBytes:&firstTwoChar length:2];
                        NSString *extension;
                        if(firstTwoChar==0x4B50) extension=@"osirixzip";//PK
                        else extension=@"dcm";
                        [data writeToFile:[incomingPath stringByAppendingPathComponent:[[NSUUID UUID]UUIDString]] atomically:NO];
                    }
                    else if ([response.MIMEType isEqualToString:@"multipart/related"])
                    {
#pragma mark ---multipart/related
                        NSString *contentType=[response.allHeaderFields objectForKey:@"Content-Type"];
                        //NSLog(@"ContentType:\"%@\"",[contentType description]);
                        NSUInteger contentTypeLength=[contentType length];
                        
                        NSRange boundary=[contentType rangeOfString:@"boundary="];
                        if (boundary.location==NSNotFound) NSLog(@"no boundary header");
                        else
                        {
                            
                            NSString *headerBoundary;
                            
                            NSRange semicolon =[contentType rangeOfString:@";" options:0 range:NSMakeRange(boundary.location,contentTypeLength-boundary.location)];
                            if (semicolon.location==NSNotFound) headerBoundary=[contentType substringWithRange:NSMakeRange(boundary.location+boundary.length, contentTypeLength-boundary.location-boundary.length)];
                            else headerBoundary=[contentType substringWithRange:NSMakeRange(boundary.location+boundary.length, semicolon.location-boundary.location-boundary.length)];
                            
                            NSData *boundaryData=[[NSString stringWithFormat:@"\r\n--%@",headerBoundary] dataUsingEncoding:NSASCIIStringEncoding];
                            //NSLog(@"boundaryData:%@",boundaryData);
                            
                            NSString *resultLog;
                            if ([contentType rangeOfString:@"type=\"application/dicom\""].location!=NSNotFound)
                            {
#pragma mark ---+++type="application/dicom"
                                [data writeToFile:@"/Users/Shared/wadorsdump" atomically:NO];
                                resultLog=[self dicomInstancesSeparatedby:boundaryData within:data];
                                NSLog(@"%@",resultLog);
                            }
                        }
                    }
                    break;
            }

        }
        requestStart=0;
    }
}

-(NSString*)dicomInstancesSeparatedby:(NSData*)boundaryData within:(NSData*)data
{
    //multipart-related: http://www.w3.org/Protocols/rfc1341/7_2_Multipart.html

#define HEADMAXSIZE 0x500
    NSUInteger dataLength=[data length];
    if (dataLength<HEADMAXSIZE)return [NSString stringWithFormat:@"smaller than %d bytes",HEADMAXSIZE];
    //4   find part metadata end \r\n\r\n
    NSRange boundaryRange;
    uint16 boundaryFollowingTwoBytes;
    NSRange rnrnRange  = [data rangeOfData:rnrn options:0 range:NSMakeRange(0, HEADMAXSIZE)];
    long fileCounter=0;
    while (rnrnRange.location != NSNotFound)
    {
        //8   find next {--boundary}
        boundaryRange=[data rangeOfData:boundaryData options:0 range:NSMakeRange(rnrnRange.location, dataLength-rnrnRange.location)];
        if (boundaryRange.location == NSNotFound) return @"application/dicom      : part not ended by boundary";

        //9   between 4 and 8, extract dicom file
        NSRange preambleRange=[data rangeOfData:dicomPreambleData options:0 range:NSMakeRange(rnrnRange.location, boundaryRange.location-rnrnRange.location)];
        if (preambleRange.location==NSNotFound) return @"application/dicom      : contents is not a dicom file";
        fileCounter++;
        //create a dicom file for this part
        [[data subdataWithRange:NSMakeRange(preambleRange.location,boundaryRange.location-preambleRange.location)]writeToFile:[incomingPath stringByAppendingPathComponent:[[NSUUID UUID]UUIDString]] atomically:NO];

        //is there at least two bytes after boundary?
        if (dataLength-boundaryRange.location-boundaryRange.length<2) return @"application/dicom      : lack of -- at the end of the response";

        //is this the end boundary?
        [data getBytes:&boundaryFollowingTwoBytes range:NSMakeRange(boundaryRange.location+boundaryRange.length,2)];
        if (boundaryFollowingTwoBytes==0x2D2D)//--
        {
            NSUInteger extraBytes=dataLength-boundaryRange.location-boundaryRange.length-2;
            if (extraBytes>0)return [NSString stringWithFormat:@"application/dicom      : %lu extra Bytes after ending --",(unsigned long)extraBytes];
            return [NSString stringWithFormat:@"application/dicom (%lu bytes / %ld files) OK",(unsigned long)dataLength,fileCounter];
        }

        //is the boundary followed by \r\n?
        if (boundaryFollowingTwoBytes!=0x0A0D) return @"application/dicom      : lack of \\r\\n at the end of boundary";
        
        //find next \r\n\r\n
        rnrnRange  = [data rangeOfData:rnrn options:0 range:NSMakeRange(boundaryRange.location+boundaryRange.length, dataLength-boundaryRange.location-boundaryRange.length)];
        if (rnrnRange.location == NSNotFound) return [NSString stringWithFormat:@"application/dicom      : %lu extra Bytes",(unsigned long)dataLength-boundaryRange.location-boundaryRange.length];
    }
    return @"new part without \r\n\r\n";
 }


@end
