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


#import "DicomDatabase+wadors.h"
#import <OsiriXAPI/NSFileManager+N2.h>
#import <OsiriXAPI/AppController.h>
#import <OsiriXAPI/ThreadsManager.h>
#import <OsiriXAPI/dicomFile.h>
#import <OsiriXAPI/NSThread+N2.h>
#import <OsiriXAPI/N2Stuff.h>
#import <OsiriXAPI/PluginManager.h>
#import <OsiriXAPI/PluginFilter.h>
#import <OsiriXAPI/N2Debug.h>

@implementation DicomDatabase (wadors)

-(NSInteger)importFilesFromIncomingDir: (NSNumber*) showGUI listenerCompressionSettings: (BOOL) listenerCompressionSettings
{
    NSMutableArray* compressedPathArray = [NSMutableArray array];
    NSThread* thread = [NSThread currentThread];
    NSUInteger addedFilesCount = 0;
    BOOL activityFeedbackShown = NO;
    
    [NSFileManager.defaultManager confirmNoIndexDirectoryAtPath:self.decompressionDirPath];
    
    N2DirectoryEnumerator *enumer = [NSFileManager.defaultManager enumeratorAtPath:self.incomingDirPath limitTo:-1];
    
    [_importFilesFromIncomingDirLock lock];
    @try {
        if ([self isFileSystemFreeSizeLimitReached]) {
            [self cleanForFreeSpace];
            if ([self isFileSystemFreeSizeLimitReached]) {
                NSLog(@"WARNING! THE DATABASE DISK IS FULL!!");
                return 0;
            }
        }
        
        NSMutableArray *filesArray = [NSMutableArray array];
#ifdef OSIRIX_LIGHT
        listenerCompressionSettings = 0;
#endif
        
        [AppController createNoIndexDirectoryIfNecessary:self.dataDirPath];
        
        int maxNumberOfFiles = [[NSUserDefaults standardUserDefaults] integerForKey:@"maxNumberOfFilesForCheckIncoming"];
        if (maxNumberOfFiles < 100) maxNumberOfFiles = 100;
        if (maxNumberOfFiles > 30000) maxNumberOfFiles = 30000;
        
        NSString *pathname;
        // NSDirectoryEnumerator *enumer = [NSFileManager.defaultManager enumeratorAtPath:self.incomingDirPath];
        
        NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval start = startTime;
        
        while([filesArray count] < maxNumberOfFiles && ([NSDate timeIntervalSinceReferenceDate]-startTime < ([[NSUserDefaults standardUserDefaults] integerForKey:@"LISTENERCHECKINTERVAL"]*3)) // don't let them wait more than (incomingdelay*3) seconds
              && (pathname = [enumer nextObject]))
        {
            if (thread.isCancelled)
                return 0;
            
            NSString *srcPath = [self.incomingDirPath stringByAppendingPathComponent:pathname];
            NSString *originalPath = srcPath;
            NSString *lastPathComponent = [srcPath lastPathComponent];
            
            if ([[lastPathComponent uppercaseString] isEqualToString:@".DS_STORE"])
            {
                [[NSFileManager defaultManager] removeItemAtPath: srcPath error: nil];
                continue;
            }
            
            if ([[lastPathComponent uppercaseString] isEqualToString:@"__MACOSX"])
            {
                [[NSFileManager defaultManager] removeItemAtPath: srcPath error: nil];
                continue;
            }
            
            //            if ([[lastPathComponent uppercaseString] hasSuffix:@".APP"]) // We don't want to scan MacOS applications
            //			{
            //				[[NSFileManager defaultManager] removeItemAtPath: srcPath error: nil];
            //				continue;
            //			}
            
            if ([lastPathComponent length] > 0 && [lastPathComponent characterAtIndex: 0] == '.')
            {
                // delete old files starting with '.'
                struct stat st;
                if ([enumer stat:&st] == 0)
                {
                    NSDate* date = [NSDate dateWithTimeIntervalSince1970:st.st_mtime];
                    if( date && [date timeIntervalSinceNow] < -60*60*24)
                    {
                        NSLog(@"deleting old incoming file %@ (date modified: %@)", srcPath, date);
                        if (srcPath)
                            [[NSFileManager defaultManager] removeItemAtPath: srcPath error: nil];
                    }
                }
                
                continue; // don't handle this file, it's probably a busy file
            }
            
            BOOL isAlias = NO;
            srcPath = [NSFileManager.defaultManager destinationOfAliasOrSymlinkAtPath:srcPath resolved:&isAlias];
            
            if( filesArray.count && !activityFeedbackShown && showGUI.boolValue) {
                [ThreadsManager.defaultManager addThreadAndStart:thread];
                [OsiriX setReceivingIcon];
                activityFeedbackShown = YES;
            }
            
            // Is it a real file? Is it writable (transfer done)?
            //					if ([[NSFileManager defaultManager] isWritableFileAtPath:srcPath] == YES)	<- Problems with CD : read-only files, but valid files
            {
                NSDictionary *fattrs = [enumer fileAttributes];	//[[NSFileManager defaultManager] fileAttributesAtPath:srcPath traverseLink: YES];
                
                if ([[fattrs objectForKey:NSFileBusy] boolValue])
                    continue;
                
                if ([[fattrs objectForKey:NSFileType] isEqualToString: NSFileTypeDirectory] == YES)
                {
                    // if alias assume nested folders should stay
                    if (!isAlias) { // Is this directory empty?? If yes, delete it!
                        BOOL dirContainsStuff = NO;
                        for (NSString* f in [[NSFileManager defaultManager] enumeratorAtPath:srcPath filesOnly:NO]) {
                            dirContainsStuff = YES;
                            break;
                        }
                        
                        if (!dirContainsStuff)
                            [[NSFileManager defaultManager] removeFileAtPath:srcPath handler:nil];
                    }
                }
                else if ([[fattrs objectForKey:NSFileSize] longLongValue] > 0)
                {
                    //if file not available for reading, do nothing
                    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:srcPath];
                    if (file)
                    {
#define WADORSSIZE 0x500
                        //=======
                        //WADORS?
                        //=======

                        BOOL wadors=NO;
                        NSMutableData *data = [NSMutableData data];
                        [data appendData:[file readDataOfLength:WADORSSIZE]];
                        
                        if( data.length >= WADORSSIZE)
                        {
                            //1   find boundary start --
                            NSData *hh = [@"--" dataUsingEncoding:NSASCIIStringEncoding];
                            NSRange hhRange  = [data rangeOfData:hh options:0 range:NSMakeRange(0, WADORSSIZE)];
                            if (hhRange.location != NSNotFound)
                            {
                                //2   find boundary end of line \r\n
                                NSData *rn = [@"\r\n" dataUsingEncoding:NSASCIIStringEncoding];
                                NSRange rnRange  = [data rangeOfData:rn options:0 range:NSMakeRange(hhRange.location, WADORSSIZE-hhRange.location)];
                                if (rnRange.location != NSNotFound)
                                {
                                    //3   subData partDelimiter: {--boundary}
                                    NSRange boundaryRange=NSMakeRange(hhRange.location, rnRange.location-hhRange.location);
                                    NSData *boundaryData=[data subdataWithRange:boundaryRange];
//conversion Ok?
                                    
                                    //4   find part metadata end \r\n\r\n
                                    NSData *rnrn = [@"\r\n\r\n" dataUsingEncoding:NSASCIIStringEncoding];
                                    NSRange rnrnRange  = [data rangeOfData:rnrn options:0 range:NSMakeRange(rnRange.location+2, WADORSSIZE-rnRange.location-2)];
                                    if (rnrnRange.location != NSNotFound)
                                    {
                                        //5   beween 3 and 4 find metadata line "Content-Type:"
                                        NSData *ct = [@"Content-Type:" dataUsingEncoding:NSASCIIStringEncoding];
                                        NSRange ctRange  = [data rangeOfData:ct options:0 range:NSMakeRange(rnRange.location, rnrnRange.location-rnRange.location)];
                                        if (ctRange.location != NSNotFound)
                                        {
                                            rnRange=[data rangeOfData:rn options:0 range:NSMakeRange(ctRange.location+13, rnrnRange.location-ctRange.location-11)];
                                            if (rnRange.location != NSNotFound)
                                            {
                                                NSString *contentTypeWithSpace=[[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(ctRange.location+13, rnRange.location-ctRange.location-13)] encoding:NSASCIIStringEncoding]autorelease];
                                                NSMutableString *contentType=[NSMutableString string];
                                                [contentType setString:[contentTypeWithSpace stringByReplacingOccurrencesOfString:@" " withString:@""]];
                                                NSLog(@"wadors Content-Type    : '%@'",contentType);
                                                if      ([contentType isEqualToString:@"application/dicom+xml"]) NSLog(@"wadors application/dicom+xml not implemented yet");
                                                else if ([contentType isEqualToString:@"application/json"])NSLog(@"wadors application/json not implemented yet");
                                                else if ([contentType isEqualToString:@"application/dicom"])
                                                {
                                                    wadors=true;
                                                    
                                                    //read the rest of file and get each dicom file
                                                    [data appendData:[file readDataToEndOfFile]];
                                                    NSUInteger dataLength = [data length];
                                                    NSLog(@"wadors data length     :  %lu",(unsigned long)dataLength);
                                                    NSLog(@"wadors boundary string : '%@'",[[[NSString alloc] initWithData:boundaryData encoding:NSASCIIStringEncoding]autorelease]);
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
                                                        if (boundaryRange.location == NSNotFound)
                                                        {
                                                            NSLog(@"part not ended by boundary in wadors application/dicom");
                                                            continue;
                                                        }
                                                        //9   between 4 and 8, extract dicom file
                                                        NSRange preambleRange=[data rangeOfData:preambleData options:0 range:NSMakeRange(rnrnRange.location, boundaryRange.location-rnrnRange.location)];
                                                        if (preambleRange.location != NSNotFound)
                                                        {
                                                            //create separate dicom file
                                                            [[data subdataWithRange:NSMakeRange(preambleRange.location,boundaryRange.location-preambleRange.location-2)]writeToFile:[self.incomingDirPath stringByAppendingPathComponent:[[NSUUID UUID]UUIDString]] atomically:NO];
                                                        }
                                                        //is there at leas two bytes after boundary?
                                                        if (dataLength-boundaryRange.location-boundaryRange.length<2)
                                                        {
                                                            NSLog(@"lack of -- at the end of wadors application/dicom");
                                                            continue;
                                                        }
                                                        
                                                        //is this the end boundary?
                                                        [data getBytes:&boundaryFollowingTwoBytes range:NSMakeRange(boundaryRange.location+boundaryRange.length,2)];
                                                        if (boundaryFollowingTwoBytes==0x2D2D)
                                                        {
                                                            NSUInteger extraBytes=dataLength-boundaryRange.location-boundaryRange.length-2;
                                                            if (extraBytes>0)NSLog(@"%lu extra Bytes after ending -- of wadors application/dicom",(unsigned long)extraBytes);
                                                            continue;
                                                        }
                                                        //is the boundary followed by \r\n?
                                                        if (boundaryFollowingTwoBytes!=0x0A0D)
                                                        {
                                                            NSLog(@"lack of \\r\\n at the end of wadors  multipart boundary");
                                                            continue;
                                                        }
                                                        
                                                        //find next \r\n\r\n
                                                        rnrnRange  = [data rangeOfData:rnrn options:0 range:NSMakeRange(boundaryRange.location+boundaryRange.length+2, dataLength-boundaryRange.location-boundaryRange.length-2)];
                                                        if (rnrnRange.location == NSNotFound)
                                                        {
                                                            NSUInteger extraBytes=dataLength-boundaryRange.location-boundaryRange.length;
                                                            if (extraBytes>0)NSLog(@"%lu extra Bytes after a part boundary of wadors application/dicom",(unsigned long)extraBytes);
                                                            continue;
                                                        }

                                                        //find metadata line "Content-Type:"

                                                        NSRange ctRange  = [data rangeOfData:ct options:0 range:NSMakeRange(boundaryRange.location+boundaryRange.length, rnrnRange.location-boundaryRange.location-boundaryRange.length)];
                                                        if (ctRange.location==NSNotFound)
                                                        {
                                                            NSLog(@"no content-type in the metadata of a part of a wadors application/dicom");
                                                            continue;
                                                        }
                                                        
                                                        //find \r\n of metadata line "Content-Type:"
                                                        rnRange=[data rangeOfData:rn options:0 range:NSMakeRange(ctRange.location+13, rnrnRange.location-ctRange.location-11)];
                                                        if (rnRange.location == NSNotFound)
                                                        {
                                                            NSLog(@"content-type not ended by \\r\\n in the metadata of a part of a wadors application/dicom");
                                                            continue;
                                                        }
                                                        NSString *contentTypeWithSpace=[[[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(ctRange.location+13, rnRange.location-ctRange.location-13)] encoding:NSASCIIStringEncoding]autorelease];
                                                        [contentType setString:[contentTypeWithSpace stringByReplacingOccurrencesOfString:@" " withString:@""]];
                                                        if (![contentType isEqualToString:@"application/dicom"])
                                                        {
                                                            NSLog(@"a part with content-type '%@' is not allowed within a wadors application/dicom",contentType);
                                                            [contentType setString:@""];
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                        }
                        [file closeFile];
                        if (wadors)[[NSFileManager defaultManager] removeFileAtPath:srcPath handler:nil];
                        
                    }
                    //==========
                    //WADORS end
                    //==========
                    
                    
                    
                    if ([[srcPath pathExtension] isEqualToString: @"zip"] || [[srcPath pathExtension] isEqualToString: @"osirixzip"])
                    {
                        NSString *compressedPath = [self.decompressionDirPath stringByAppendingPathComponent: lastPathComponent];
                        [[NSFileManager defaultManager] moveItemAtPath:srcPath toPath:compressedPath error:NULL];
                        [compressedPathArray addObject: compressedPath];
                    }
                    else
                    {
                        BOOL isDicomFile, isJPEGCompressed, isImage;
                        NSString *dstPath = [self.dataDirPath stringByAppendingPathComponent: lastPathComponent];
                        
                        isDicomFile = [DicomFile isDICOMFile:srcPath compressed: &isJPEGCompressed image: &isImage];
                        
                        if (isDicomFile == YES ||
                            (([DicomFile isFVTiffFile:srcPath] ||
                              [DicomFile isTiffFile:srcPath] ||
                              [DicomFile isNRRDFile:srcPath])
                             && [[NSFileManager defaultManager] fileExistsAtPath:dstPath] == NO))
                        {
                            if (isDicomFile && isImage)
                            {
                                if ((isJPEGCompressed == YES && listenerCompressionSettings == 1) || (isJPEGCompressed == NO && listenerCompressionSettings == 2
#ifndef OSIRIX_LIGHT
                                                                                                      && [DicomDatabase fileNeedsDecompression: srcPath]
#else
#endif
                                                                                                      ))
                                {
                                    NSString *compressedPath = [self.decompressionDirPath stringByAppendingPathComponent: lastPathComponent];
                                    [[NSFileManager defaultManager] moveItemAtPath:srcPath toPath:compressedPath error:NULL];
                                    [compressedPathArray addObject: compressedPath];
                                    continue;
                                }
                                
                                dstPath = [self uniquePathForNewDataFileWithExtension:@"dcm"];
                            }
                            else dstPath = [self uniquePathForNewDataFileWithExtension:[[srcPath pathExtension] lowercaseString]];
                            
                            BOOL result;
                            
                            if (isAlias)
                            {
                                result = [[NSFileManager defaultManager] copyPath:srcPath toPath: dstPath handler:nil];
                                [[NSFileManager defaultManager] removeFileAtPath:originalPath handler:nil];
                            }
                            else
                            {
                                result = [[NSFileManager defaultManager] moveItemAtPath:srcPath toPath: dstPath error:NULL];
                            }
                            
                            if (result == YES)
                                [filesArray addObject:dstPath];
                        }
                        else // DELETE or MOVE THIS UNKNOWN FILE ?
                        {
                            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"DELETEFILELISTENER"])
                                [[NSFileManager defaultManager] removeItemAtPath:srcPath error:NULL];
                            else {
                                if (![NSFileManager.defaultManager moveItemAtPath:srcPath toPath:[self.errorsDirPath stringByAppendingPathComponent:lastPathComponent] error:NULL])
                                    [NSFileManager.defaultManager removeFileAtPath:srcPath handler:nil];
                            }
                        }
                    }
                }
            }
            
            if( [NSDate timeIntervalSinceReferenceDate] - start > 0.5)
            {
                thread.status =  N2LocalizedSingularPluralCount( filesArray.count, NSLocalizedString(@"file", nil), NSLocalizedString(@"files", nil));
                start = [NSDate timeIntervalSinceReferenceDate];
            }
        }
        
        if( filesArray.count)
            thread.status = N2LocalizedSingularPluralCount( filesArray.count, NSLocalizedString(@"file", nil), NSLocalizedString(@"files", nil));
        
        if ([filesArray count] > 0)
        {
            //				if ( [[NSUserDefaults standardUserDefaults] boolForKey:@"ANONYMIZELISTENER"] == YES)
            //					[self listenerAnonymizeFiles: filesArray];
            
            if ([[PluginManager preProcessPlugins] count])
            {
                thread.status = [NSString stringWithFormat:NSLocalizedString(@"Preprocessing %d files with %d plugins...", nil), filesArray.count, [[PluginManager preProcessPlugins] count]];
                for (id filter in [PluginManager preProcessPlugins])
                {
                    @try
                    {
                        [PluginManager startProtectForCrashWithFilter: filter];
                        [filter processFiles: filesArray];
                        [PluginManager endProtectForCrash];
                    }
                    @catch (NSException* e)
                    {
                        N2LogExceptionWithStackTrace(e);
                    }
                }
            }
            
            thread.status = [NSString stringWithFormat:NSLocalizedString(@"Processing %@...", nil), N2LocalizedSingularPluralCount(filesArray.count, NSLocalizedString(@"file", nil),NSLocalizedString(@"files", nil))];
            
            NSArray* addedFiles = nil;
            if( thread.isCancelled == NO)
                addedFiles = [self addFilesAtPaths:filesArray]; // these are IDs!
            
            addedFilesCount = addedFiles.count;
            
            if (!addedFiles) // Add failed.... Keep these files: move them back to the INCOMING folder and try again later....
            {
                NSString *dstPath;
                int x = 0;
                
                NSLog( @"------------ Move the files back to the incoming folder...");
                
                for( NSString *file in filesArray)
                {
                    do
                    {
                        dstPath = [self.incomingDirPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%d", x]];
                        x++;
                    }
                    while( [[NSFileManager defaultManager] fileExistsAtPath:dstPath] == YES);
                    
                    [[NSFileManager defaultManager] moveItemAtPath: file toPath: dstPath error: NULL];
                }
            }
            
        }
        
    }
    @catch (NSException* e)
    {
        N2LogExceptionWithStackTrace(e);
    }
    @finally
    {
        [_importFilesFromIncomingDirLock unlock];
        if (activityFeedbackShown)
            [OsiriX unsetReceivingIcon];
    }
    
    if (enumer.nextObject) // there is more data
        [self performSelector:@selector(initiateImportFilesFromIncomingDirUnlessAlreadyImporting) withObject:nil afterDelay:0];
    
#ifndef OSIRIX_LIGHT
    if ([compressedPathArray count] > 0) // there are files to compress/decompress in the decompression dir
    {
        if (listenerCompressionSettings == 1 || listenerCompressionSettings == 0) // decompress, listenerCompressionSettings == 0 for zip support!
        { 
            //            [self performSelectorInBackground:@selector(_threadDecompressToIncoming:) withObject:compressedPathArray];
            
            @synchronized (_decompressQueue) {
                [_decompressQueue addObjectsFromArray:compressedPathArray];
            }
            
            [self kickstartCompressDecompress];
            
            //            [self initiateDecompressFilesAtPaths: compressedPathArray intoDirAtPath: self.incomingDirPath];
        }
        else if (listenerCompressionSettings == 2) // compress
        { 
            //            [self performSelectorInBackground:@selector(_threadCompressToIncoming:) withObject:compressedPathArray];
            
            @synchronized (_decompressQueue) {
                [_compressQueue addObjectsFromArray:compressedPathArray];
            }
            
            [self kickstartCompressDecompress];
            
            //            [self initiateCompressFilesAtPaths: compressedPathArray intoDirAtPath: self.incomingDirPath];
        }
    }
#endif
    
    return addedFilesCount;
}


@end
