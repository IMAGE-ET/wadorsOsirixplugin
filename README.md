# wadors.osirixplugin
adds [wado-rs](http://dicom.nema.org/medical/dicom/current/output/chtml/part18/sect_6.5.html) capabilities to OsiriX.

# how to install or compile
A zipped binary compilation of the plugin is available [here](https://github.com/opendicom/wadors.osirixplugin/blob/master/wadors.osirixplugin.zip)

The compilation of wadors.osirixplugin requires MacOSX 10.8 sdk (because OsriX 5.9 opensource uses this toolkit). Modern versions of Xcode (7.3+) need you to edit the MinimumSDKVersion in this file to use older SDKs: /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Info.plist.

The compilation 32-bit of the plugin can be debugged together with OsiriX 5.9 opensource (which is available in targets 32-bit only).

# how it works

##osirix://?methodName=DownloadURL&Display=YES&URL='{URL}'
This is a nice feature of OsiriX in harmony with Safari on the Mac platform, where when invoking such an URL from Safari, Safari delegates it to OsiriX, which sends the request and receives the response. The response is obtained by the class WADODownloader. 

We have included in our plugin a category on WADODownloader which redefines method WADODownload.

## current implementation

On purpose, we don't want concurrent downloads.

We had to add the http header 'Accept: multipart/related;type=application/dicom' when the URL contains '/dcm4chee-arc/aets/'.' in order to specify http wado rest.

There are in fact some more reason to rewrite the requests. For instance a wado-rs on study level may generate an unacceptably long stream. A nice workaround would be that the "re-writer" issue a qido at series level and then rewrite the wado into various series level wado-rs."