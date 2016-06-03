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


#import "WADODownload+wadors.h"

#import <OsiriXAPI/browserController.h>
#import <OsiriXAPI/DicomDatabase.h>
#import <OsiriXAPI/NSThread+N2.h>
#include <libkern/OSAtomic.h>
#import <OsiriXAPI/dicomFile.h>
#import <OsiriXAPI/LogManager.h>
#import <OsiriXAPI/N2Debug.h>
#import <OsiriXAPI/NSString+N2.h>


@implementation WADODownload(wadors)

-(NSString*)wadorsExtractDicomFilesFrom:(NSMutableData*)data toPath:(NSString*)path
{
    //multipart-related: http://www.w3.org/Protocols/rfc1341/7_2_Multipart.html

#define WADORSSIZE 0x500
    NSUInteger dataLength=[data length];
    if (dataLength<WADORSSIZE)return @"smaller than  v";
    
    //1   find boundary start --
    NSData *hh = [@"--" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange hhRange  = [data rangeOfData:hh options:0 range:NSMakeRange(0,WADORSSIZE)];
    if (hhRange.location==NSNotFound)return @"no -- whithin WADORSSIZE";

    //2   find boundary end of line \r\n
    NSData *rn = [@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange rnRange  = [data rangeOfData:rn options:0 range:NSMakeRange(hhRange.location, WADORSSIZE-hhRange.location)];
    if (rnRange.location == NSNotFound)return @"no \\r\\n to end boundary";

    //3   subData partDelimiter: {--boundary}
    NSRange boundaryRange=NSMakeRange(hhRange.location, rnRange.location-hhRange.location);
    NSData *boundaryData=[data subdataWithRange:boundaryRange];
    NSString *boundaryString=[[[NSString alloc] initWithData:boundaryData encoding:NSASCIIStringEncoding]autorelease];
    if (!boundaryString) return [@"boundary not ascci\r\n" stringByAppendingString:[boundaryData description]];
    
    //4   find part metadata end \r\n\r\n
    NSData *rnrn = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange rnrnRange  = [data rangeOfData:rnrn options:0 range:NSMakeRange(rnRange.location, WADORSSIZE-rnRange.location)];
    if (rnrnRange.location == NSNotFound)return @"no \\r\\n\\r\\n to separate boundary+metadata from contents";

    //5   beween 3 and 4 find metadata line "Content-Type:"
    NSData *ct = [@"Content-Type:" dataUsingEncoding:NSASCIIStringEncoding];
    NSRange ctRange  = [data rangeOfData:ct options:0 range:NSMakeRange(rnRange.location, rnrnRange.location-rnRange.location)];
    if (ctRange.location == NSNotFound) return @"no Content-Type of the first item";

    rnRange=[data rangeOfData:rn options:0 range:NSMakeRange(ctRange.location+13, rnrnRange.location-ctRange.location-11)];
    if (rnRange.location == NSNotFound) return @"no \\r\\n ending the Content-Type of the first item";

    NSString *contentTypeWithSpace=[[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(ctRange.location+13, rnRange.location-ctRange.location-13)] encoding:NSASCIIStringEncoding]autorelease];
    if (!contentTypeWithSpace) return @"can not read Content-Type string of the first item";
    NSMutableString *contentType=[NSMutableString string];
    [contentType setString:[contentTypeWithSpace stringByReplacingOccurrencesOfString:@" " withString:@""]];
    NSLog(@"wadors Content-Type    : '%@'",contentType);
    if      ([contentType isEqualToString:@"application/dicom+xml"]) return @"wadors application/dicom+xml not implemented yet";
    else if ([contentType isEqualToString:@"application/json"]) return @"wadors application/json not implemented yet";
    else if ([contentType isEqualToString:@"application/dicom"])
    {
        //application/dicom
        
        NSLog(@"wadors data length     :  %lu",(unsigned long)dataLength);
        NSLog(@"wadors boundary string : '%@'",contentType);
        
        NSMutableData *preambleData=[NSMutableData dataWithLength:128];
        UInt32 dicmSignature=0x4D434944;//DICM
        NSData *dicmSignatureData=[NSData dataWithBytes:&dicmSignature length:4];
        [preambleData appendData:dicmSignatureData];
        
        uint16 boundaryFollowingTwoBytes=0;
        while ([contentType isEqualToString:@"application/dicom"])
        {
            [contentType setString:@""];
                                    
            //8   find next {--boundary}
            boundaryRange=[data rangeOfData:boundaryData options:0 range:NSMakeRange(rnrnRange.location, dataLength-rnrnRange.location)];
            if (boundaryRange.location == NSNotFound) return @"application/dicom      : part not ended by boundary";

            //9   between 4 and 8, extract dicom file
            NSRange preambleRange=[data rangeOfData:preambleData options:0 range:NSMakeRange(rnrnRange.location, boundaryRange.location-rnrnRange.location)];
            if (preambleRange.location==NSNotFound) return @"application/dicom      : contents is not a dicom file";
            
            //create a dicom file for this part
            [[data subdataWithRange:NSMakeRange(preambleRange.location,boundaryRange.location-preambleRange.location-2)]writeToFile:[path stringByAppendingPathComponent:[[NSUUID UUID]UUIDString]] atomically:NO];

            //is there at least two bytes after boundary?
            if (dataLength-boundaryRange.location-boundaryRange.length<2) return @"application/dicom      : lack of -- at the end of the response";

            //is this the end boundary?
            [data getBytes:&boundaryFollowingTwoBytes range:NSMakeRange(boundaryRange.location+boundaryRange.length,2)];
            if (boundaryFollowingTwoBytes==0x2D2D)//--
            {
                NSUInteger extraBytes=dataLength-boundaryRange.location-boundaryRange.length-2;
                if (extraBytes>0)return [NSString stringWithFormat:@"application/dicom      : %lu extra Bytes after ending --",(unsigned long)extraBytes];
                return @"application/dicom      : response OK";
            }

            //is the boundary followed by \r\n?
            if (boundaryFollowingTwoBytes!=0x0A0D) return @"application/dicom      : lack of \\r\\n at the end of boundary";
            
            //find next \r\n\r\n
            rnrnRange  = [data rangeOfData:rnrn options:0 range:NSMakeRange(boundaryRange.location+boundaryRange.length, dataLength-boundaryRange.location-boundaryRange.length)];
            if (rnrnRange.location == NSNotFound) return [NSString stringWithFormat:@"application/dicom      : %lu extra Bytes",(unsigned long)dataLength-boundaryRange.location-boundaryRange.length];
            
            //find metadata line "Content-Type:"
            NSRange ctRange  = [data rangeOfData:ct options:0 range:NSMakeRange(boundaryRange.location+boundaryRange.length, rnrnRange.location-boundaryRange.location-boundaryRange.length)];
            if (ctRange.location==NSNotFound) return @"application/dicom      : no content-type in the metadata of a part";
            
            //find \r\n of metadata line "Content-Type:"
            rnRange=[data rangeOfData:rn options:0 range:NSMakeRange(ctRange.location+13, rnrnRange.location-ctRange.location-11)];
            if (rnRange.location == NSNotFound) return (@"application/dicom      : Content-Type not ended by \\r\\n");
            NSString *contentTypeWithSpace=[[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(ctRange.location+13, rnRange.location-ctRange.location-13)] encoding:NSASCIIStringEncoding]autorelease];
            [contentType setString:[contentTypeWithSpace stringByReplacingOccurrencesOfString:@" " withString:@""]];
        }
    }
    return [NSString stringWithFormat:@"application/dicom      : Content-Type '%@' not allowed",contentType];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    if( connection)
    {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        
        NSString *path = [[DicomDatabase activeLocalDatabase] incomingDirPath];
        
        NSString *key = [NSString stringWithFormat:@"%ld", (long) connection];
        
        NSMutableData *d = [[WADODownloadDictionary objectForKey: key] objectForKey: @"data"];
        
        NSString *wadors=[self wadorsExtractDicomFilesFrom:d toPath:path];
        
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
                                [logEntry setValue: [[[WADODownloadDictionary objectForKey: key] objectForKey: @"url"] host] forKey:@"logCallingAET"];
                                
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
                [[NSFileManager defaultManager] moveItemAtPath: [path stringByAppendingPathComponent: filename] toPath: [path stringByAppendingPathComponent: [filename substringFromIndex: 1]] error: nil];
            }
        }
        [d setLength: 0]; // Free the memory immediately
        [WADODownloadDictionary removeObjectForKey: key];
        
        WADOThreads--;
        
        [pool release];
    }
    else N2LogStackTrace( @"connection == nil");
}

- (void) WADODownload: (NSArray*) urlToDownload
{
    if( urlToDownload.count == 0)
    {
        NSLog( @"**** urlToDownload.count == 0 in WADODownload");
        return;
    }
    
    NSMutableArray *connectionsArray = [NSMutableArray array];
    
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    self.baseStatus = [[NSThread currentThread] status];
    
    @try
    {
        if( [urlToDownload count])
            urlToDownload = [[NSSet setWithArray: urlToDownload] allObjects]; // UNIQUE OBJECTS !
        
        if( [urlToDownload count])
        {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#ifndef NDEBUG
            NSLog( @"------ WADO downloading : %d files", (int) [urlToDownload count]);
#endif
            firstWadoErrorDisplayed = NO;
            
            if( showErrorMessage == NO)
                firstWadoErrorDisplayed = YES; // dont show errors
            
            [WADODownloadDictionary release];
            WADODownloadDictionary = [[NSMutableDictionary dictionary] retain];
            
            int WADOMaximumConcurrentDownloads = [[NSUserDefaults standardUserDefaults] integerForKey: @"WADOMaximumConcurrentDownloads"];
            if( WADOMaximumConcurrentDownloads < 1)
                WADOMaximumConcurrentDownloads = 1;
            
            float timeout = [[NSUserDefaults standardUserDefaults] floatForKey: @"WADOTimeout"];
            if( timeout < 240) timeout = 240;
            
#ifndef NDEBUG
            NSLog( @"------ WADO parameters: timeout:%2.2f [secs] / WADOMaximumConcurrentDownloads:%d [URLRequests]", timeout, WADOMaximumConcurrentDownloads);
#endif
            self.countOfSuccesses = 0;
            WADOTotal = WADOThreads = [urlToDownload count];
            
            NSTimeInterval retrieveStartingDate = [NSDate timeIntervalSinceReferenceDate];
            
            BOOL aborted = NO;
            for( NSURL *url in urlToDownload)
            {
                while( [WADODownloadDictionary count] > WADOMaximumConcurrentDownloads) //Dont download more than XXX images at the same time
                {
                    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
                    
                    if( _abortAssociation || [NSThread currentThread].isCancelled || [[NSFileManager defaultManager] fileExistsAtPath: @"/tmp/kill_all_storescu"] || [NSDate timeIntervalSinceReferenceDate] - retrieveStartingDate > timeout)
                    {
                        aborted = YES;
                        break;
                    }
                }
                retrieveStartingDate = [NSDate timeIntervalSinceReferenceDate];
                
                @try
                {
                    if( [[url scheme] isEqualToString: @"https"])
                        [NSURLRequest setAllowsAnyHTTPSCertificate:YES forHost:[url host]];
                }
                @catch (NSException *e)
                {
                    NSLog( @"***** exception in %s: %@", __PRETTY_FUNCTION__, e);
                }
                
                NSMutableURLRequest *theRequest=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:timeout];
                [theRequest setHTTPMethod:@"GET"];
                if ([url.absoluteString containsString:@"/dcm4chee-arc/aets/"])
                {
                    NSLog(@"%@\r\nAccept: multipart/related;type=application/dicom",url.absoluteString);
                    [theRequest setValue:@"multipart/related;type=application/dicom" forHTTPHeaderField:@"Accept"];
                }
                
                NSURLConnection *downloadConnection = [NSURLConnection connectionWithRequest:theRequest delegate: self];
                
                if( downloadConnection)
                {
                    [WADODownloadDictionary setObject: [NSDictionary dictionaryWithObjectsAndKeys: url, @"url", [NSMutableData data], @"data", nil] forKey: [NSString stringWithFormat:@"%ld", (long) downloadConnection]];
                    [downloadConnection start];
                    [connectionsArray addObject: downloadConnection];
                }
                
                if( downloadConnection == nil)
                    WADOThreads--;
                
                if( _abortAssociation || [NSThread currentThread].isCancelled || [[NSFileManager defaultManager] fileExistsAtPath: @"/tmp/kill_all_storescu"] || [NSDate timeIntervalSinceReferenceDate] - retrieveStartingDate > timeout)
                {
                    aborted = YES;
                    break;
                }
            }
            
            if( aborted == NO)
            {
                while( WADOThreads > 0)
                {
                    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
                    
                    if( _abortAssociation || [NSThread currentThread].isCancelled || [[NSFileManager defaultManager] fileExistsAtPath: @"/tmp/kill_all_storescu"]  || [NSDate timeIntervalSinceReferenceDate] - retrieveStartingDate > timeout)
                    {
                        aborted = YES;
                        break;
                    }
                }
                
                if( aborted == NO && [[WADODownloadDictionary allKeys] count] > 0)
                    NSLog( @"**** [[WADODownloadDictionary allKeys] count] > 0");
                
                [[DicomDatabase activeLocalDatabase] initiateImportFilesFromIncomingDirUnlessAlreadyImporting];
            }
            
            if( aborted) [logEntry setValue:@"Incomplete" forKey:@"logMessage"];
            else [logEntry setValue:@"Complete" forKey:@"logMessage"];
            
            [[LogManager currentLogManager] addLogLine: logEntry];
            
            if( aborted)
            {
                for( NSURLConnection *connection in connectionsArray)
                    [connection cancel];
            }
            
            [WADODownloadDictionary release];
            WADODownloadDictionary = nil;
            
            [logEntry release];
            logEntry = nil;
            
            [pool release];
            
#ifndef NDEBUG
            if( aborted)
                NSLog( @"------ WADO downloading ABORTED");
            else
                NSLog( @"------ WADO downloading : %d files - finished (errors: %d / total: %d)", (int) [urlToDownload count], (int) (urlToDownload.count - countOfSuccesses), (int) urlToDownload.count);
#endif
        }
    }
    @catch (NSException *exception) {
        N2LogException( exception);
    }
    @finally {
        [pool release];
    }
}



@end
