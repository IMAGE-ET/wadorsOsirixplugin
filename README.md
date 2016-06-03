# wadors.osirixplugin
adds [wado-rs](http://dicom.nema.org/medical/dicom/current/output/chtml/part18/sect_6.5.html) capabilities to OsiriX.

# how to install or compile
A zipped binary compilation of the plugin is available [here](https://github.com/opendicom/wadors.osirixplugin/blob/master/wadors.osirixplugin.zip)

The compilation of wadors.osirixplugin requires XCode 7.2.1 or lower with MacOSX 10.8 sdk (because OsriX 5.9 opensource used this toolkit). Needs to be tested in XCode debugger in version 32 bit.

# how it works

##osirix://?methodName=DownloadURL&Display=YES&URL='{URL}'
This is a nice feature of OsiriX in harmony with Safari on the Mac platform, where when invoking such an URL from Safari, Safari delegates it to OsiriX, which sends the request and receives the response. The response is obtained by the class WADODownloader. The method

-(void)connectionDidFinishLoading:(NSURLConnection *)connection;

provides an NSData with the response. We analyze it and create DICOM files in INCOMING.noindex for each of the parts.

## add header to the request
NSURLConnection supports NSMutableURLRequest where it is posible to add headers to the request URL.

We add 'Accept: multipart/related;type=application/dicom' when the URL contains '/dcm4chee-arc/aets/'.'