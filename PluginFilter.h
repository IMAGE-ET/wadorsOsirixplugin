/*=========================================================================
  Program:   OsiriX

  Copyright (c) OsiriX Team
  All rights reserved.
  Distributed under GNU - GPL
  
  See http://www.osirix-viewer.com/copyright.html for details.

     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.
=========================================================================*/



#import <Cocoa/Cocoa.h>

@interface PluginFilter : NSObject {
}

+ (PluginFilter *)filter;


/** This function is the entry point of Pre-Process plugins */
- (long) processFiles: (NSArray*) files;


/** This function is called at the OsiriX startup, if you need to do some memory allocation, etc. */
- (void) initPlugin;

/** Opportunity for plugins to make Menu changes if necessary */
- (void)setMenus;

@end
