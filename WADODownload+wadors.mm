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
#import "wadoQueue.h"

@implementation WADODownload(wadors)

- (void) WADODownload: (NSArray*) urlToDownload
{
    if( urlToDownload.count == 0) return;
    float timeout = [[NSUserDefaults standardUserDefaults] floatForKey: @"WADOTimeout"];
    if( timeout < 240) timeout = 240;
    NSTimeInterval retrieveStartingDate;

        for( NSURL *url in [[NSSet setWithArray: urlToDownload]allObjects])
        {
            //starting point in time
            retrieveStartingDate = [NSDate timeIntervalSinceReferenceDate];
            NSLog(@"retrieveStartingDate:%f",retrieveStartingDate);
            
            //request
            NSMutableURLRequest *theRequest=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:timeout];
            [theRequest setHTTPMethod:@"GET"];
            //if ([url.absoluteString containsString:@"/dcm4chee-arc/aets/"])
            //{
                NSLog(@"%@\r\nAccept: multipartrelated;type=application/dicom",url.absoluteString);
                [theRequest setValue:@"multipart/related;type=application/dicom" forHTTPHeaderField:@"Accept"];
            //}
            
            //connection
            [wadoQueue queueRequest:theRequest];
        }//end each url
        /*
         
         if(
         [NSThread currentThread].isCancelled
         || [NSDate timeIntervalSinceReferenceDate] - retrieveStartingDate > timeout
         )
         {
         aborted = YES;
         break;
         }

                [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
                
                if( _abortAssociation || [NSThread currentThread].isCancelled || [[NSFileManager defaultManager] fileExistsAtPath: @"/tmp/kill_all_storescu"]  || [NSDate timeIntervalSinceReferenceDate] - retrieveStartingDate > timeout)
                {
                    for( NSURLConnection *connection in connectionsArray)
                        [connection cancel];
                }
            }
         */
}


@end
