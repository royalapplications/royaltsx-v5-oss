//
//  iTermOptionalComponentDownloadWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/27/18.
//

#import "iTermOptionalComponentDownloadWindowController.h"

#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@protocol iTermOptionalComponentDownloadPhaseDelegate<NSObject>
- (void)optionalComponentDownloadPhaseDidComplete:(iTermOptionalComponentDownloadPhase *)sender;
- (void)optionalComponentDownloadPhase:(iTermOptionalComponentDownloadPhase *)sender
                    didProgressToBytes:(double)bytesWritten
                               ofTotal:(double)totalBytes;
@end

@interface iTermOptionalComponentDownloadPhase()<NSURLSessionDownloadDelegate>
@property (nonatomic, weak) id<iTermOptionalComponentDownloadPhaseDelegate> delegate;
@property (atomic) BOOL downloading;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, strong) NSURLSession *urlSession;
@end

@implementation iTermOptionalComponentDownloadPhase

- (instancetype)initWithURL:(NSURL *)url
                      title:(NSString *)title
           nextPhaseFactory:(iTermOptionalComponentDownloadPhase *(^)(iTermOptionalComponentDownloadPhase *))nextPhaseFactory {
    self = [super init];
    if (self) {
        _url = [url copy];
        _title = [title copy];
        _nextPhaseFactory = [nextPhaseFactory copy];
    }
    return self;
}

- (void)download {
    assert(!_urlSession);
    assert(!_task);

    self.downloading = YES;
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    _urlSession = [NSURLSession sessionWithConfiguration:sessionConfig
                                                delegate:self
                                           delegateQueue:nil];
    _task = [_urlSession downloadTaskWithURL:_url];
    [_task resume];
}

- (void)cancel {
    self.downloading = NO;
    [_task cancel];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate optionalComponentDownloadPhase:self didProgressToBytes:totalBytesWritten ofTotal:downloadTask.countOfBytesExpectedToReceive];
    });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    self.downloading = NO;
    _stream = [NSInputStream inputStreamWithURL:location];
    [_stream open];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
    self.downloading = NO;
    if (!error) {
        _urlSession = nil;
        _task = nil;
        int statusCode = [[NSHTTPURLResponse castFrom:task.response] statusCode];
        if (statusCode != 200) {
            error = [NSError errorWithDomain:@"com.iterm2" code:1 userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server returned status code %@: %@", @(statusCode), [NSHTTPURLResponse localizedStringForStatusCode:statusCode] ] }];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_error = error;
        [self.delegate optionalComponentDownloadPhaseDidComplete:self];
    });
}

@end

@implementation iTermManifestDownloadPhase

- (instancetype)initWithURL:(NSURL *)url
           nextPhaseFactory:(iTermOptionalComponentDownloadPhase *(^)(iTermOptionalComponentDownloadPhase *))nextPhaseFactory {
    return [super initWithURL:url title:@"Finding latest version???" nextPhaseFactory:nextPhaseFactory];
}

- (NSDictionary *)parsedManifestFromInputStream:(NSInputStream *)stream {
    id obj = [NSJSONSerialization JSONObjectWithStream:stream options:0 error:nil];
    NSDictionary *dict = [NSDictionary castFrom:obj];
    if (dict[@"url"] && dict[@"signature"] && dict[@"version"]) {
        return dict;
    } else {
        return nil;
    }
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
    if (!error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *dict = [self parsedManifestFromInputStream:self.stream];
            NSError *innerError = nil;
            if (dict) {
                self->_nextURL = [NSURL URLWithString:dict[@"url"]];
                self->_signature = dict[@"signature"];
                self->_version = [dict[@"version"] intValue];
            } else {
                innerError = [NSError errorWithDomain:@"com.iterm2" code:2 userInfo:@{ NSLocalizedDescriptionKey: @"Manifest missing required field" }];
            }
            [super URLSession:session task:task didCompleteWithError:innerError];
        });
    } else {
        [super URLSession:session task:task didCompleteWithError:error];
    }
}

@end

@implementation iTermPayloadDownloadPhase

- (instancetype)initWithURL:(NSURL *)url expectedSignature:(NSString *)expectedSignature {
    self = [super initWithURL:url title:@"Downloading Python runtime???" nextPhaseFactory:nil];
    if (self) {
        _expectedSignature = [expectedSignature copy];
    }
    return self;
}

@end

@interface iTermOptionalComponentDownloadWindowController ()<iTermOptionalComponentDownloadPhaseDelegate>

@end

@implementation iTermOptionalComponentDownloadWindowController {
    IBOutlet NSTextField *_titleLabel;
    IBOutlet NSTextField *_progressLabel;
    IBOutlet NSProgressIndicator *_progressIndicator;
    IBOutlet NSButton *_button;
    iTermOptionalComponentDownloadPhase *_firstPhase;
    BOOL _showingMessage;
}

- (void)windowDidLoad {
    [super windowDidLoad];

    _titleLabel.stringValue = @"Initializing???";
    _progressLabel.stringValue = [NSString stringWithFormat:@""];
}

- (void)beginPhase:(iTermOptionalComponentDownloadPhase *)phase {
    _showingMessage = NO;
    assert(!_currentPhase.downloading);
    if (!_currentPhase) {
        _firstPhase = phase;
    }
    _currentPhase = phase;
    _titleLabel.stringValue = phase.title;
    phase.delegate = self;
    [phase download];
    _progressLabel.stringValue = [NSString stringWithFormat:@"Connecting???"];
    _button.enabled = YES;
    _button.title = @"Cancel";
}

- (void)showMessage:(NSString *)message {
    _showingMessage = YES;
    _titleLabel.stringValue = message;
    _progressLabel.stringValue = @"";
    _button.enabled = YES;
    _button.title = @"OK";
}

- (IBAction)button:(id)sender {
    if (_showingMessage) {
        [self.window close];
    } else if (_currentPhase.downloading) {
        [_currentPhase cancel];
    } else {
        [self beginPhase:_firstPhase];
    }
}

- (void)downloadDidFailWithError:(NSError *)error {
    _button.enabled = YES;
    _button.title = @"Try Again";
    if (error.code == -999) {
        _progressLabel.stringValue = @"Canceled";
    } else {
        _progressLabel.stringValue = error.localizedDescription;
    }
    _progressIndicator.doubleValue = 0;
    iTermOptionalComponentDownloadPhase *phase = _currentPhase;
    _currentPhase = nil;
    self.completion(phase);
}

#pragma mark - iTermOptionalComponentDownloadPhaseDelegate

- (void)optionalComponentDownloadPhaseDidComplete:(iTermOptionalComponentDownloadPhase *)sender {
    if (sender.error) {
        [self downloadDidFailWithError:sender.error];
    } else if (sender.nextPhaseFactory) {
        iTermOptionalComponentDownloadPhase *nextPhase = sender.nextPhaseFactory(_currentPhase);
        if (nextPhase) {
            [self beginPhase:nextPhase];
        } else {
            iTermOptionalComponentDownloadPhase *phase = _currentPhase;
            _currentPhase = nil;
            self.completion(phase);
        }
    } else {
        _button.enabled = NO;
        _progressLabel.stringValue = @"Finished";
        iTermOptionalComponentDownloadPhase *phase = _currentPhase;
        _currentPhase = nil;
        self.completion(phase);
    }
}

- (void)optionalComponentDownloadPhase:(iTermOptionalComponentDownloadPhase *)sender
                    didProgressToBytes:(double)bytesWritten
                               ofTotal:(double)totalBytes {
    self->_progressIndicator.doubleValue = bytesWritten / totalBytes;
    self->_progressLabel.stringValue = [NSString stringWithFormat:@"%@ of %@",
                                        [NSString it_formatBytes:bytesWritten],
                                        [NSString it_formatBytes:totalBytes]];
}

@end
