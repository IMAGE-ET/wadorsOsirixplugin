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
static NSMutableArray *requests;
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

static NSDate *requestStart;
static NSTimeInterval timeout;

@implementation wadoQueue

#pragma mark singleton



+(wadoQueue*)queue
{
    if (sharedWadoQueue == nil) return [wadoQueue queueRequest:nil];
    return sharedWadoQueue;
}

+(wadoQueue*)queueRequest:(NSMutableURLRequest*)request
{
    if (sharedWadoQueue == nil)
    {
        sharedWadoQueue = [[super allocWithZone:NULL] init];
        requests=[[NSMutableArray array]retain];
        incomingPath=[[DicomDatabase activeLocalDatabase] incomingDirPath];
        
        UInt32 dicmSignature=0x4D434944;//DICM
        NSMutableData *first132=[NSMutableData dataWithLength:128];
        [first132 appendData:[NSData dataWithBytes:&dicmSignature length:4]];
        dicomPreambleData =[[NSData alloc]initWithData:first132];

        uint16 pk=0x1234;
        pkSignatureData=[[NSData alloc]initWithBytes:&pk length:2];
        
        imageRMT=@[
                   @"image/jpeg",
                   @"image/gif",
                   @"image/png",
                   @"image/jp2"
                   ];
        videoRMT=@[
                   @"video/mpeg",
                   @"video/mp4",
                   @"video/jpeg",
                  ];
        textRMT=@[
                   @"text/html",
                   @"text/plain",
                   @"text/xml",
                   @"text/rtf",
                   @"application/pdf"
                   ];//CDA returned as text/xml
        dicomMT=@[
                  @"application/dicom",
                  @"application/dicom+xml",
                  @"application/dicom+json"
                 ];
        buMT=@[
               @"application/octet-stream"
              ];
        bcMT=@[
               @"image/*",
               @"video/*"
               ];

        hh = [@"--" dataUsingEncoding:NSASCIIStringEncoding];
        rn = [@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];
        rnrn = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
        
        timeout=[[NSUserDefaults standardUserDefaults] floatForKey: @"WADOTimeout"];
        if( timeout < 240) timeout = 240;
        [self performSelectorOnMainThread: @selector(startLooping:) withObject:sharedWadoQueue waitUntilDone:NO];
    }
    if (request)[requests addObject:[request copy]];
    if ([requests count]==1) [sharedWadoQueue nextHTTPRequest];
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
    //requestStart keeps the time of the request start until the request is completed, then it goes back to nill value. We use it to avoid more than a request at a time
    //NSLog(@"%@",[[NSDate date]description]);
    if (!requestStart || ([requestStart dateByAddingTimeInterval:timeout] < [NSDate date]))
    {
        if (requestStart)[requestStart release];
        requestStart=[NSDate date];
    
        //NSLog(@"%@",[[requests objectAtIndex:0]description]);
        
        NSHTTPURLResponse *response;
        //URL properties: expectedContentLength, MIMEType, textEncodingName
        //HTTP properties: statusCode, allHeaderFields
        NSError *error;
        NSData *data=[NSURLConnection sendSynchronousRequest:[requests objectAtIndex:0]
                                           returningResponse:&response
                                                       error:&error];
        if (error)
        {
            NSLog(@"%@\r\n%@",[[requests objectAtIndex:0]description],[error description]);
            [requests removeObjectAtIndex:0];
            return;
        }
        switch (response.statusCode)
        {

#pragma mark 200
            case 200://NSLog(@"200-OK");
                if ([response.MIMEType isEqualToString:@"multipart/related"])
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
                        //NSLog(@"boundaryData: [%@ description]",boundaryData);
                        
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

        /*
        if ([wadors hasPrefix:@"application/dicom      :"]) NSLog(@"%@",wadors);
        else
        {
            NSString *extension = @"dcm";
            
            if( [d length] > 2)
            {
                countOfSuccesses++;
                
                uint16 firstTwoChar;
                [d getBytes:&firstTwoChar length:2];
                
                if(firstTwoChar==0x4B50) extension = @"osirixzip";//PK
                
                
                
                NSString *filename = [[NSString stringWithFormat:@".WADO-%d-%ld", WADOThreads, (long) self] stringByAppendingPathExtension: extension];
                
                [d writeToFile: [path stringByAppendingPathComponent: filename] atomically: YES];
                
                if( WADOThreads == WADOTotal) // The first file !
                {
                    [[DicomDatabase activeLocalDatabase] initiateImportFilesFromIncomingDirUnlessAlreadyImporting];
                    
                    @try
                    {
                        if (!logEntry && [DicomFile isDICOMFile: [path stringByAppendingPathComponent: filename]])
                        {
                            DicomFile *dcmFile = [[DicomFile alloc] init: [path stringByAppendingPathComponent: filename]];
                            
                            @try
                            {
                                logEntry = [[NSMutableDictionary dictionary] retain];
                                
                                [logEntry setValue: [NSString stringWithFormat: @"%lf", [[NSDate date] timeIntervalSince1970]] forKey:@"logUID"];
                                [logEntry setValue: [NSDate date] forKey:@"logStartTime"];
                                [logEntry setValue: @"Receive" forKey:@"logType"];
                                [logEntry setValue: [[[WADOnextHTTPResponseDictionary objectForKey: key] objectForKey: @"url"] host] forKey:@"logCallingAET"];
                                
                                if ([dcmFile elementForKey: @"patientName"])
                                    [logEntry setValue: [dcmFile elementForKey: @"patientName"] forKey: @"logPatientName"];
                                
                                if ([dcmFile elementForKey: @"studyDescription"])
                                    [logEntry setValue:[dcmFile elementForKey: @"studyDescription"] forKey:@"logStudyDescription"];
                                
                                [logEntry setValue:[NSNumber numberWithInt: WADOTotal] forKey:@"logNumberTotal"];
                            }
                            @catch (NSException *e) {
                                N2LogException( e);
                            }
                            [dcmFile release];
                        }
                    }
                    @catch (NSException *exception) {
                        N2LogException( exception);
                    }
                }
                
                [logEntry setValue:[NSNumber numberWithInt: 1 + WADOTotal - WADOThreads] forKey:@"logNumberReceived"];
                
                [logEntry setValue:[NSDate date] forKey:@"logEndTime"];
                [logEntry setValue:@"In Progress" forKey:@"logMessage"];
                
                [[LogManager currentLogManager] addLogLine: logEntry];
                
                if( WADOGrandTotal)
                    [[NSThread currentThread] setProgress: (float) ((WADOTotal - WADOThreads) + WADOBaseTotal) / (float) WADOGrandTotal];
                else if( WADOTotal)
                    [[NSThread currentThread] setProgress: 1.0 - (float) WADOThreads / (float) WADOTotal];
                
                // To remove the '.'
                [[NSFileManager queueManager] moveItemAtPath: [path stringByAppendingPathComponent: filename] toPath: [path stringByAppendingPathComponent: [filename substringFromIndex: 1]] error: nil];
            }
        }
         */
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
