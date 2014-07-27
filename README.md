URLConnectionSample
===================

NSURLConnection and watching upload progress and download progress.


Sample code of the how to use:

```objective-c

URLConnection *connection = [[URLConnection alloc] init];
NSHTTPURLResponse *response = nil;
NSError *error = nil;
NSData *result = [connection sendSynchronousRequestWithProgressReport:request returningResponse:&response error:&error
	uploadProgressHandler:^BOOL(float progress) {
		return YES;
	}
	downloadProgressHandler:^BOOL(float progress) {
		return YES;
	}
];

```

Note:

  * If no HTTP body in the request, uploadProgressHandler will not be called.
  * If the progress parameter of downloadProgressHandler is NaN, The connection would not have received a total size of content.
  * If the uploadProgressHandler returns NO, Upload will be canceled.
  * If the downloadProgressHandler returns NO, Download will be canceled.
