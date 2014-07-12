URLConnectionSample
===================

NSURLConnection and watching download progress.


Sample code of the how to use:

```objective-c

URLConnection *connection = [[URLConnection alloc] init];
NSHTTPURLResponse *response = nil;
NSError *error = nil;
NSData *result = [connection sendSynchronousRequestWithProgressReport:request returningResponse:&response error:&error progressHandler:^BOOL(float progress) {
		return YES;
}];

```

Note:

  * If the progress parameter of progressHandler is NaN, The connection would not have received a total size of content.
  * If the progressHandler returns NO, Download will be canceled.
