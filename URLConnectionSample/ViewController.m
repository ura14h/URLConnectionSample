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
- (NSData *)sendSynchronousRequestWithProgressReport:(NSURLRequest *)request returningResponse:(NSURLResponse *__autoreleasing *)response error:(NSError *__autoreleasing *)error progressHandler:(BOOL (^)(float progress))progressHandler;

@end

#pragma mark - URLConnection.m

@interface URLConnection () <NSURLConnectionDataDelegate>

@property (strong, nonatomic) NSURLRequest *request;
@property (strong, nonatomic) NSURLResponse *response;
@property (strong, nonatomic) NSMutableData *result;
@property (strong, nonatomic) NSError *error;
@property (copy, nonatomic) BOOL (^progressHandler)(float progress);

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
		_progressHandler = nil;
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
	_progressHandler = nil;
	_connection = nil;
}

- (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse *__autoreleasing *)response error:(NSError *__autoreleasing *)error
{
	return [NSURLConnection sendSynchronousRequest:request returningResponse:response error:error];
}

- (NSData *)sendSynchronousRequestWithProgressReport:(NSURLRequest *)request returningResponse:(NSURLResponse *__autoreleasing *)response error:(NSError *__autoreleasing *)error progressHandler:(BOOL (^)(float progress))progressHandler
{
	_request = request;
	_response = nil;
	_result = [NSMutableData data];
	_error = nil;
	_progressHandler = progressHandler;
	_done = NO;
	
	[NSThread detachNewThreadSelector:@selector(startDownload) toTarget:self withObject:nil];
	while (!_done) {
		[NSThread sleepForTimeInterval:0.05];
	}
	
	_connection = nil;
	_request = nil;
	_progressHandler = nil;
	
	*response = _response;
	*error = _error;
	return _result;
}

- (void)startDownload
{
	@autoreleasepool {
		_connection = [[NSURLConnection alloc] initWithRequest:_request delegate:self startImmediately:NO];
		[_connection start];
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate distantFuture]];
	}
}

- (void)cancelDownload
{
	[_connection cancel];
	
	NSDictionary *info = @{
		NSLocalizedDescriptionKey: @"Downloading is canceled by user action.",
		NSURLErrorFailingURLErrorKey: _request.URL,
		NSURLErrorFailingURLStringErrorKey: _request.URL.absoluteString,
	};
	_error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:info];
	_done = YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	_response = response;
	if (!_progressHandler(0.0)) {
		[self cancelDownload];
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
	
	if (!_progressHandler(progress)) {
		[self cancelDownload];
	}
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	if (!_progressHandler(1.0)) {
		[self cancelDownload];
		return;
	}

	_error = nil;
	_done = YES;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	_error = error;
	_done = YES;
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
	
	_urlTextField.text = @"http://";
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
		NSData *result = [connection sendSynchronousRequestWithProgressReport:request returningResponse:&response error:&error progressHandler:^BOOL(float progress) {
			NSLog(@"progress=%f", progress);
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

- (IBAction)cancelDownloadAsync:(id)sender
{
	_cancel = YES;
}

@end
