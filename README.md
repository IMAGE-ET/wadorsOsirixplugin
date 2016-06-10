# wadors.osirixplugin
adds [wado-rs](http://dicom.nema.org/medical/dicom/current/output/chtml/part18/sect_6.5.html) capabilities to OsiriX.

# how to install or compile
A zipped binary compilation of the plugin is available [here](https://github.com/opendicom/wadors.osirixplugin/blob/master/wadors.osirixplugin.zip)

The compilation of wadors.osirixplugin requires MacOSX 10.8 sdk (because OsriX 5.9 opensource uses this toolkit). Modern versions of Xcode (7.3+) need you to edit the MinimumSDKVersion in this file to use older SDKs: /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Info.plist.

The compilation 32-bit of the plugin can be debugged together with OsiriX 5.9 opensource (which is available in targets 32-bit only).

# how it works

##osirix://?methodName=DownloadURL&Display=YES&URL='{URL}'
This is a nice feature of OsiriX in harmony with Safari on the Mac platform: when invoking such an URL from Safari, Safari delegates it to OsiriX, which sends the request and receives the response. The response is obtained by the class WADODownloader. 

We have included in our plugin a category on WADODownloader which redefines method WADODownload.

## current implementation

On purpose, we don't want concurrent downloads.

We complete (rewrite) the wado rest urls and add the http header 'Accept: multipart/related;type=application/dicom'. We do so when the URL contains '/dcm4chee-arc/' y '/studies/'.