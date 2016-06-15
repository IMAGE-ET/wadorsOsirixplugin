# wadors.osirixplugin
adds [wado-rs](http://dicom.nema.org/medical/dicom/current/output/chtml/part18/sect_6.5.html) capabilities to OsiriX.

# how to install or compile
A zipped binary compilation of the plugin is available [here](https://github.com/opendicom/wadorsOsirixplugin/raw/master/wadors.osirixplugin.zip)

The compilation of wadors.osirixplugin requires MacOSX 10.8 sdk (because the open source 32 bit OsiriX 5.9 opensource uses this toolkit). It works also on MacOSX 10.10 sdk 64 bit, which seems to be the toolkit used by OsiriX 7.5+

Modern versions of Xcode (7.3+) need you to edit the MinimumSDKVersion in this file to use older SDKs: /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Info.plist.

# how it works

##osirix://?methodName=DownloadURL&Display=YES&URL='{URL}'
This is a nice feature of OsiriX in harmony with Safari on the Mac platform: when invoking such an URL from Safari, Safari delegates it to OsiriX, which sends the request and receives the response. The response is obtained by the class WADODownloader. 

We have included in our plugin a category on WADODownloader which redefines the method WADODownload in order to be processed by a new class called wadoQueue, without dependency on the native implementation of wado in OsiriX.

## current implementation

We don't want concurrent downloads, since this can provoke timeouts when downloading for instance several mamograms concurrently. In order to execute each wado consecutively, we created a singleton class, with a FIFO array queuing new wado URLs. 

The proper execution of the wado is not directly called at registration of new URLs, but is  fired as another tread from a timer, each second. The process fired executes as much wado requests as posible during a timout period (by default 240 segs). If all the wados were executed before the end of the timeout, the process is closed. During the execution of a process, new processes fired are aborted imediately.

The code for wado execution takes into account wado url, wado rs and OsiriX propietary wado zip. When the URL of wado contains "requestType=WADO", it is treated as wado uri or wado zip (if the body of the answer starts with "PK"). When it doesn´t, it is treated as wado rs. In this case, we add  the http header 'Accept: multipart/related;type=application/dicom' to the request.