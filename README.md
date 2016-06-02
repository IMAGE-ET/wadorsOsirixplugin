# wadors.osirixplugin
adds [wado-rs](http://dicom.nema.org/medical/dicom/current/output/chtml/part18/sect_6.5.html) capabilities to OsiriX.

# how to install or compile
A zipped binary compilation of the plugin is available [here](https://github.com/opendicom/wadors.osirixplugin/blob/master/osirixplugin/wadors.osirixplugin.zip)

The compilation of wadors.osirixplugin requires XCode 7.2.1 or lower with MacOSX 10.8 sdk (because OsriX 5.9 opensource used this toolkit). Needs to be tested in XCode debugger in version 32 bit.

# how it works
##osirix://?methodName=DownloadURL&Display=YES&URL='{URL}'
This is a nice feature of OsiriX in harmony with Safari on the Mac platform, where when invoking such an URL from Safari, Safari delegates it to OsiriX, which sends the request and receives the response. Once completed the response is written as a file into the INCOMING.noindex folder, which works as spooler of new entries. New files are analized and incorporated into OsiriX Database. The analisis includes the oportunity por "Pre-Process" plugins to access the file, modify it and eventually destroy it before it is incorporated into OsiriX Database.

The bad luck is that the call to the plugin occurs after OsiriX checking that the file is a DICOM file. The multipart/related contents of a wadors response as a whole doesn´t pass this checkpoint.

That´s why we had to use a category on OsiriX class DicomDatabase, in order to override the method 

-(NSInteger)importFilesFromIncomingDir: (NSNumber*) showGUI listenerCompressionSettings: (BOOL) listenerCompressionSettings

which is responsible for the whole spooling process.