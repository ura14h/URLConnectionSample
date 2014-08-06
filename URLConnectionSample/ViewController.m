//
//  ViewController.m
//  URLConnectionSample
//
//  Created by Hiroki Ishiura on 2014/07/12.
//  Copyright (c) 2014年 Hiroki Ishiura. All rights reserved.
//

#import "ViewController.h"

#pragma mark - URLConnection.h

@interface URLConnection : NSObject

- (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse *__autoreleasing *)response error:(NSError *__autoreleasing *)error;
- (NSData *)sendSynchronousRequestWithProgressReport:(NSURLRequest *)request returningResponse:(NSURLResponse *__autoreleasing *)response error:(NSError *__autoreleasing *)error uploadProgressHandler:(BOOL (^)(float progress))uploadProgressHandler downloadProgressHandler:(BOOL (^)(float progress))downloadProgressHandler;

@end

#pragma mark - URLConnection.m

@interface URLConnection () <NSURLConnectionDataDelegate>

@property (strong, nonatomic) NSURLRequest *request;
@property (strong, nonatomic) NSURLResponse *response;
@property (strong, nonatomic) NSMutableData *result;
@property (strong, nonatomic) NSError *error;
@property (copy, nonatomic) BOOL (^uploadProgressHandler)(float progress);
@property (copy, nonatomic) BOOL (^downloadProgressHandler)(float progress);

@property (strong, nonatomic) NSURLConnection *connection;
@property (assign, nonatomic) BOOL done;

@end

@implementation URLConnection

- (instancetype)init
{
    self = [super init];
    if (self) {
		_request = nil;
		_response = nil;
		_result = nil;
		_error = nil;
		_uploadProgressHandler = nil;
		_downloadProgressHandler = nil;
		_connection = nil;
    }
    return self;
}

- (void)dealloc
{
	_request = nil;
	_response = nil;
	_result = nil;
	_error = nil;
	_uploadProgressHandler = nil;
	_downloadProgressHandler = nil;
	_connection = nil;
}

- (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse *__autoreleasing *)response error:(NSError *__autoreleasing *)error
{
	return [NSURLConnection sendSynchronousRequest:request returningResponse:response error:error];
}

- (NSData *)sendSynchronousRequestWithProgressReport:(NSURLRequest *)request returningResponse:(NSURLResponse *__autoreleasing *)response error:(NSError *__autoreleasing *)error uploadProgressHandler:(BOOL (^)(float progress))uploadProgressHandler downloadProgressHandler:(BOOL (^)(float progress))downloadProgressHandler
{
	_request = request;
	_response = nil;
	_result = [NSMutableData data];
	_error = nil;
	_uploadProgressHandler = uploadProgressHandler;
	_downloadProgressHandler = downloadProgressHandler;
	_done = NO;
	
	[NSThread detachNewThreadSelector:@selector(startTask) toTarget:self withObject:nil];
	while (!_done) {
		[NSThread sleepForTimeInterval:0.05];
	}
	
	_connection = nil;
	_request = nil;
	_uploadProgressHandler = nil;
	_downloadProgressHandler = nil;
	
	*response = _response;
	*error = _error;
	return _result;
}

- (void)startTask
{
	@autoreleasepool {
		_connection = [[NSURLConnection alloc] initWithRequest:_request delegate:self startImmediately:NO];
		[_connection start];
		
		if (_request.HTTPBody && _request.HTTPBody.length > 0) {
			if (_uploadProgressHandler && !_uploadProgressHandler(0.0)) {
				[self cancelTask];
				return;
			}
		}
		
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate distantFuture]];
	}
}

- (void)cancelTask
{
	[_connection cancel];
	
	_result = nil;
	NSDictionary *info = @{
		NSLocalizedDescriptionKey: @"Request is canceled by user action.",
		NSURLErrorFailingURLErrorKey: _request.URL,
		NSURLErrorFailingURLStringErrorKey: _request.URL.absoluteString,
	};
	_error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:info];
	_done = YES;
	[NSThread exit];
}

- (void)endTask:(NSError *)error
{
	_error = error;
	_done = YES;
	[NSThread exit];
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
	float progress;
	if (totalBytesExpectedToWrite > 0) {
		progress = (double)totalBytesWritten / (double)totalBytesExpectedToWrite;
		if (progress < 0.0 || progress > 1.0) {
			// 0.0 -> on startTask
			return;
		}
	} else {
		progress = NAN;
	}
	
	if (_uploadProgressHandler && !_uploadProgressHandler(progress)) {
		[self cancelTask];
	}
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	_response = response;
	if (_downloadProgressHandler && !_downloadProgressHandler(0.0)) {
		[self cancelTask];
	}
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
	[_result appendData:data];
	
	float progress;
	if (_response.expectedContentLength == NSURLResponseUnknownLength) {
		progress = NAN;
	} else {
		progress = (double)_result.length / (double)_response.expectedContentLength;
		if (progress <= 0.0 || progress >= 1.0) {
			// 0.0 -> on connection:didReceiveResponse:
			// 1.0 -> on connectionDidFinishLoading:
			return;
		}
	}
	
	if (_downloadProgressHandler && !_downloadProgressHandler(progress)) {
		[self cancelTask];
	}
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	if (_downloadProgressHandler) {
		if (_downloadProgressHandler(1.0)) {
			[self endTask:nil];
		} else {
			[self cancelTask];
		}
	} else {
		[self endTask:nil];
	}
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	[self endTask:error];
}

@end

#pragma mark - ViewController.m

@interface ViewController () <UITextFieldDelegate>

@property (weak, nonatomic) IBOutlet UITextField *urlTextField;
@property (weak, nonatomic) IBOutlet UIProgressView *progressView;
@property (weak, nonatomic) IBOutlet UILabel *resultLabel;

@property (strong, nonatomic) dispatch_queue_t mainQueue;
@property (strong, nonatomic) dispatch_queue_t commandQueue;
@property (assign, nonatomic) BOOL cancel;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	
	_urlTextField.text = @"http://localhost/";
	_resultLabel.text = @"Ready.";
	_progressView.progress = 0.0;
	
	_mainQueue = dispatch_get_main_queue();
	_commandQueue = dispatch_queue_create("commandQueue", NULL);
	_cancel = NO;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc
{
	_mainQueue = nil;
	_commandQueue = nil;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	[_urlTextField resignFirstResponder];
    return YES;
}

- (IBAction)downloadSync:(id)sender
{
	_progressView.progress = 0.0;
	_resultLabel.text = @"Started.";

	_cancel = NO;
	NSLog(@"enqueued a task.");
	dispatch_async(self.commandQueue, ^{
		NSLog(@"started a task.");
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_urlTextField.text]];
		request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
		request.timeoutInterval = 10.0;
		
		URLConnection *connection = [[URLConnection alloc] init];
		NSHTTPURLResponse *response = nil;
		NSError *error = nil;
		NSData *result = [connection sendSynchronousRequest:request returningResponse:&response error:&error];
		NSLog(@"response = %@", response.description);
		NSLog(@"result.length = %ld", (long)(result ? result.length : 0));
		NSLog(@"error = %@", error.description);
		
		float progress;
		NSString *message;
		if (response.statusCode == 200 && !error && result.length > 0) {
			progress = 1.0;
			message = @"Finished.";
		} else {
			progress = 0.0;
			message = @"Aborted.";
		}
		
		connection = nil;
		dispatch_async(self.mainQueue, ^{
			_progressView.progress = progress;
			_resultLabel.text = message;
		});
		NSLog(@"finished the task.");
	});
}

- (IBAction)downloadAsync:(id)sender
{
	_progressView.progress = 0.0;
	_resultLabel.text = @"Started.";
	
	_cancel = NO;
	NSLog(@"enqueued a task.");
	dispatch_async(self.commandQueue, ^{
		NSLog(@"started a task.");
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_urlTextField.text]];
		request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
		request.timeoutInterval = 10.0;

		URLConnection *connection = [[URLConnection alloc] init];
		NSHTTPURLResponse *response = nil;
		NSError *error = nil;
		NSData *result = [connection sendSynchronousRequestWithProgressReport:request returningResponse:&response error:&error uploadProgressHandler:nil downloadProgressHandler:^BOOL(float progress) {
			NSLog(@"download progress=%f", progress);
			if (!isnan(progress)) {
				dispatch_async(self.mainQueue, ^{
					_progressView.progress = progress;
				});
			}
			return !_cancel;
		}];
		NSLog(@"response = %@", response.description);
		NSLog(@"result.length = %ld", (long)(result ? result.length : 0));
		NSLog(@"error = %@", error.description);

		NSString *message;
		if (response.statusCode == 200 && !error && result.length > 0) {
			message = @"Finished.";
		} else {
			message = @"Aborted.";
		}
		
		connection = nil;
		dispatch_async(self.mainQueue, ^{
			_resultLabel.text = message;
		});
		NSLog(@"finished the task.");
	});
}

- (IBAction)uploadAsync:(id)sender
{
	_progressView.progress = 0.0;
	_resultLabel.text = @"Started.";
	
	_cancel = NO;
	NSLog(@"enqueued a task.");
	dispatch_async(self.commandQueue, ^{
		NSLog(@"started a task.");
		
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_urlTextField.text]];
		request.cachePolicy = NSURLRequestReloadIgnoringCacheData;
		request.timeoutInterval = 10.0;
		request.HTTPMethod = @"POST";
		NSMutableData *body = [NSMutableData data];
		{
			NSString *boundary = @"743bbc65af0e5364cc6e0fc50787794c";
			NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary];
			[request addValue:contentType forHTTPHeaderField: @"Content-Type"];
			[body appendData:[[NSString stringWithFormat:@"\r\n--%@\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
			[body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"data\"; filename=\"upload.dat\"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
			[body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
			[body appendData:(NSData *)[[NSMutableData alloc] initWithLength:1024*1024*10]];
			[body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
		}
		request.HTTPBody = (NSData *)body;
		
		URLConnection *connection = [[URLConnection alloc] init];
		NSHTTPURLResponse *response = nil;
		NSError *error = nil;
		NSData *result = [connection sendSynchronousRequestWithProgressReport:request returningResponse:&response error:&error uploadProgressHandler:^BOOL(float progress) {
			NSLog(@"upload progress=%f", progress);
			if (!isnan(progress)) {
				dispatch_async(self.mainQueue, ^{
					_progressView.progress = progress;
				});
			}
			return !_cancel;
		} downloadProgressHandler:nil];
	
		NSLog(@"response = %@", response.description);
		NSLog(@"result.length = %ld", (long)(result ? result.length : 0));
		NSLog(@"error = %@", error.description);
		
		NSString *message;
		if (response.statusCode == 200 && !error && result.length > 0) {
			message = @"Finished.";
		} else {
			message = @"Aborted.";
		}
		
		connection = nil;
		dispatch_async(self.mainQueue, ^{
			_resultLabel.text = message;
		});
		NSLog(@"finished the task.");
	});
}

- (IBAction)cancel:(id)sender
{
	_cancel = YES;
}

@end
