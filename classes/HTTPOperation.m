/*
    File:       HTTPOperation.m
    Contains:   An NSOperation that runs an HTTP request.
    Written by: dragonlist 
    Copyright:  MIT 
*/

#import "HTTPOperation.h"

@interface HTTPOperation ()

// Read/write versions of public properties

@property (copy,   readwrite) NSURLRequest *        lastRequest;
@property (copy,   readwrite) NSHTTPURLResponse *   lastResponse;

// Internal properties

@property (retain, readwrite) NSURLConnection *     connection;
@property (assign, readwrite) BOOL                  firstData;
@property (retain, readwrite) NSMutableData *       dataAccumulator;

@end

@implementation QHTTPOperation

#pragma mark * Initialise and finalise

- (id)initWithRequest:(NSURLRequest *)request
    // See comment in header.
{
    // any thread
    assert(request != nil);
    assert([request URL] != nil);
    // Because we require an NSHTTPURLResponse, we only support HTTP and HTTPS URLs.
    assert([[[[request URL] scheme] lowercaseString] isEqual:@"http"] || [[[[request URL] scheme] lowercaseString] isEqual:@"https"]);
    self = [super init];
    if (self != nil) {
        #if TARGET_OS_EMBEDDED || TARGET_IPHONE_SIMULATOR
            static const NSUInteger kPlatformReductionFactor = 4;
        #else
            static const NSUInteger kPlatformReductionFactor = 1;
        #endif
        self->_request = [request copy];
        self->_defaultResponseSize = 1 * 1024 * 1024 / kPlatformReductionFactor;
        self->_maximumResponseSize = 4 * 1024 * 1024 / kPlatformReductionFactor;
        self->_firstData = YES;
    }
    return self;
}

- (id)initWithURL:(NSURL *)url
    // See comment in header.
{
    assert(url != nil);
    return [self initWithRequest:[NSURLRequest requestWithURL:url]];
}

- (void)dealloc
{
    // any thread
    [self->_request release];
    [self->_acceptableStatusCodes release];
    [self->_acceptableContentTypes release];
    [self->_responseOutputStream release];
    assert(self->_connection == nil);               // should have been shut down by now
    [self->_dataAccumulator release];
    [self->_lastRequest release];
    [self->_lastResponse release];
    [self->_responseBody release];
    [super dealloc];
}

#pragma mark * Properties

// We write our own settings for many properties because we want to bounce 
// sets that occur in the wrong state.  And, given that we've written the 
// setter anyway, we also avoid KVO notifications when the value doesn't change.

@synthesize request = _request;

@synthesize acceptableStatusCodes = _acceptableStatusCodes;

+ (BOOL)automaticallyNotifiesObserversOfAcceptableStatusCodes
{
    return NO;
}

- (void)setAcceptableStatusCodes:(NSIndexSet *)newValue
{
    if (self.state != kQRunLoopOperationStateInited) {
        assert(NO);
    } else {
        if (newValue != self->_acceptableStatusCodes) {
            [self willChangeValueForKey:@"acceptableStatusCodes"];
            [self->_acceptableStatusCodes autorelease];
            self->_acceptableStatusCodes = [newValue copy];
            [self didChangeValueForKey:@"acceptableStatusCodes"];
        }
    }
}

@synthesize acceptableContentTypes = _acceptableContentTypes;

+ (BOOL)automaticallyNotifiesObserversOfAcceptableContentTypes
{
    return NO;
}

- (void)setAcceptableContentTypes:(NSSet *)newValue
{
    if (self.state != kQRunLoopOperationStateInited) {
        assert(NO);
    } else {
        if (newValue != self->_acceptableContentTypes) {
            [self willChangeValueForKey:@"acceptableContentTypes"];
            [self->_acceptableContentTypes autorelease];
            self->_acceptableContentTypes = [newValue copy];
            [self didChangeValueForKey:@"acceptableContentTypes"];
        }
    }
}

@synthesize responseOutputStream = _responseOutputStream;

+ (BOOL)automaticallyNotifiesObserversOfResponseOutputStream
{
    return NO;
}

- (void)setResponseOutputStream:(NSOutputStream *)newValue
{
    if (self.dataAccumulator != nil) {
        assert(NO);
    } else {
        if (newValue != self->_responseOutputStream) {
            [self willChangeValueForKey:@"responseOutputStream"];
            [self->_responseOutputStream autorelease];
            self->_responseOutputStream = [newValue retain];
            [self didChangeValueForKey:@"responseOutputStream"];
        }
    }
}

@synthesize defaultResponseSize   = _defaultResponseSize;

+ (BOOL)automaticallyNotifiesObserversOfDefaultResponseSize
{
    return NO;
}

- (void)setDefaultResponseSize:(NSUInteger)newValue
{
    if (self.dataAccumulator != nil) {
        assert(NO);
    } else {
        if (newValue != self->_defaultResponseSize) {
            [self willChangeValueForKey:@"defaultResponseSize"];
            self->_defaultResponseSize = newValue;
            [self didChangeValueForKey:@"defaultResponseSize"];
        }
    }
}

@synthesize maximumResponseSize = _maximumResponseSize;

+ (BOOL)automaticallyNotifiesObserversOfMaximumResponseSize
{
    return NO;
}

- (void)setMaximumResponseSize:(NSUInteger)newValue
{
    if (self.dataAccumulator != nil) {
        assert(NO);
    } else {
        if (newValue != self->_maximumResponseSize) {
            [self willChangeValueForKey:@"maximumResponseSize"];
            self->_maximumResponseSize = newValue;
            [self didChangeValueForKey:@"maximumResponseSize"];
        }
    }
}

@synthesize lastRequest     = _lastRequest;
@synthesize lastResponse    = _lastResponse;
@synthesize responseBody    = _responseBody;

@synthesize connection      = _connection;
@synthesize firstData       = _firstData;
@synthesize dataAccumulator = _dataAccumulator;

- (NSURL *)URL
{
    return [self.request URL];
}

- (BOOL)isStatusCodeAcceptable
{
    NSIndexSet *    acceptableStatusCodes;
    NSInteger       statusCode;
    
    assert(self.lastResponse != nil);
    
    acceptableStatusCodes = self.acceptableStatusCodes;
    if (acceptableStatusCodes == nil) {
        acceptableStatusCodes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(200, 100)];
    }
    assert(acceptableStatusCodes != nil);
    
    statusCode = [self.lastResponse statusCode];
    return (statusCode >= 0) && [acceptableStatusCodes containsIndex: (NSUInteger) statusCode];
}

- (BOOL)isContentTypeAcceptable
{
    NSString *  contentType;
    
    assert(self.lastResponse != nil);
    contentType = [self.lastResponse MIMEType];
    return (self.acceptableContentTypes == nil) || ((contentType != nil) && [self.acceptableContentTypes containsObject:contentType]);
}

#pragma mark * Start and finish overrides

- (void)operationDidStart
    // Called by QRunLoopOperation when the operation starts.  This kicks of an 
    // asynchronous NSURLConnection.
{
    assert(self.isActualRunLoopThread);
    assert(self.state == kQRunLoopOperationStateExecuting);
    
    assert(self.defaultResponseSize > 0);
    assert(self.maximumResponseSize > 0);
    assert(self.defaultResponseSize <= self.maximumResponseSize);
    
    assert(self.request != nil);
    
    assert(self.connection == nil);
    if ([self isCancelled]) {
        [self finishWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
    } else {
    
        // Create a connection that's scheduled in the required run loop modes.
        
        self.connection = [[[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO] autorelease];
        assert(self.connection != nil);
        
        for (NSString * mode in self.actualRunLoopModes) {
            [self.connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:mode];
        }
        
        [self.connection start];
    }
}

- (void)operationWillFinish
    // Called by QRunLoopOperation when the operation has finished.  We 
    // do various bits of tidying up.
{
    assert(self.isActualRunLoopThread);
    assert(self.state == kQRunLoopOperationStateExecuting);

    // I can't think of any circumstances under which the debug delay timer 
    // might still be running at this point, but add an assert just to be sure.
    
    #if ! defined(NDEBUG)
        assert(self.debugDelayTimer == nil);
    #endif

    [self.connection cancel];
    self.connection = nil;

    // If we have an output stream, close it at this point.  We might never 
    // have actually opened this stream but, AFAICT, closing an unopened stream 
    // doesn't hurt. 

    if (self.responseOutputStream != nil) {
        [self.responseOutputStream close];
    }
}

- (void)finishWithError:(NSError *)error
    // We override -finishWithError: just so we can handle our debug delay.
{
    // If a debug delay was set, don't finish now but rather start the debug delay timer 
    // and have it do the actual finish.  We clear self.debugDelay so that the next 
    // time this code runs its doesn't do this again.
    
    #if ! defined(NDEBUG)
        if (self.debugDelay > 0.0) {
            assert(self.debugDelayTimer == nil);
            self.debugDelayTimer = [NSTimer timerWithTimeInterval:self.debugDelay target:self selector:@selector(debugDelayTimerDone:) userInfo:self.error repeats:NO];
            assert(self.debugDelayTimer != nil);
            for (NSString * mode in self.actualRunLoopModes) {
                [[NSRunLoop currentRunLoop] addTimer:self.debugDelayTimer forMode:mode];
            }
            self.debugDelay = 0.0;
            return;
        } 
    #endif

    [super finishWithError:error];
}


#pragma mark * NSURLConnection delegate callbacks

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response
    // See comment in header.
{
    assert(self.isActualRunLoopThread);
    assert(connection == self.connection);
    #pragma unused(connection)
    assert( (response == nil) || [response isKindOfClass:[NSHTTPURLResponse class]] );

    self.lastRequest  = request;
    self.lastResponse = (NSHTTPURLResponse *) response;
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
    // See comment in header.
{
    assert(self.isActualRunLoopThread);
    assert(connection == self.connection);
    #pragma unused(connection)
    assert([response isKindOfClass:[NSHTTPURLResponse class]]);

    self.lastResponse = (NSHTTPURLResponse *) response;
    
    // We don't check the status code here because we want to give the client an opportunity 
    // to get the data of the error message.  Perhaps we /should/ check the content type 
    // here, but I'm not sure whether that's the right thing to do.
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
    // See comment in header.
{
    BOOL    success;
    
    assert(self.isActualRunLoopThread);
    assert(connection == self.connection);
    #pragma unused(connection)
    assert(data != nil);
    
    // If we don't yet have a destination for the data, calculate one.  Note that, even 
    // if there is an output stream, we don't use it for error responses.
    
    success = YES;
    if (self.firstData) {
        assert(self.dataAccumulator == nil);
        
        if ( (self.responseOutputStream == nil) || ! self.isStatusCodeAcceptable ) {
            long long   length;
            
            assert(self.dataAccumulator == nil);
            
            length = [self.lastResponse expectedContentLength];
            if (length == NSURLResponseUnknownLength) {
                length = self.defaultResponseSize;
            }
            if (length <= (long long) self.maximumResponseSize) {
                self.dataAccumulator = [NSMutableData dataWithCapacity:(NSUInteger)length];
            } else {
                [self finishWithError:[NSError errorWithDomain:kQHTTPOperationErrorDomain code:kQHTTPOperationErrorResponseTooLarge userInfo:nil]];
                success = NO;
            }
        }
        
        // If the data is going to an output stream, open it.
        
        if (success) {
            if (self.dataAccumulator == nil) {
                assert(self.responseOutputStream != nil);
                [self.responseOutputStream open];
            }
        }
        
        self.firstData = NO;
    }
    
    // Write the data to its destination.

    if (success) {
        if (self.dataAccumulator != nil) {
            if ( ([self.dataAccumulator length] + [data length]) <= self.maximumResponseSize ) {
                [self.dataAccumulator appendData:data];
            } else {
                [self finishWithError:[NSError errorWithDomain:kQHTTPOperationErrorDomain code:kQHTTPOperationErrorResponseTooLarge userInfo:nil]];
            }
        } else {
            NSUInteger      dataOffset;
            NSUInteger      dataLength;
            const uint8_t * dataPtr;
            NSError *       error;
            NSInteger       bytesWritten;

            assert(self.responseOutputStream != nil);

            dataOffset = 0;
            dataLength = [data length];
            dataPtr    = [data bytes];
            error      = nil;
            do {
                if (dataOffset == dataLength) {
                    break;
                }
                bytesWritten = [self.responseOutputStream write:&dataPtr[dataOffset] maxLength:dataLength - dataOffset];
                if (bytesWritten <= 0) {
                    error = [self.responseOutputStream streamError];
                    if (error == nil) {
                        error = [NSError errorWithDomain:kQHTTPOperationErrorDomain code:kQHTTPOperationErrorOnOutputStream userInfo:nil];
                    }
                    break;
                } else {
                    dataOffset += bytesWritten;
                }
            } while (YES);
            
            if (error != nil) {
                [self finishWithError:error];
            }
        }
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
    // See comment in header.
{
    assert(self.isActualRunLoopThread);
    assert(connection == self.connection);
    #pragma unused(connection)
    
    assert(self.lastResponse != nil);

    // Swap the data accumulator over to the response data so that we don't trigger a copy.
    
    assert(self->_responseBody == nil);
    self->_responseBody = self->_dataAccumulator;
    self->_dataAccumulator = nil;
    
    if ( ! self.isStatusCodeAcceptable ) {
        [self finishWithError:[NSError errorWithDomain:kQHTTPOperationErrorDomain code:self.lastResponse.statusCode userInfo:nil]];
    } else if ( ! self.isContentTypeAcceptable ) {
        [self finishWithError:[NSError errorWithDomain:kQHTTPOperationErrorDomain code:kQHTTPOperationErrorBadContentType userInfo:nil]];
    } else {
        [self finishWithError:nil];
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
    // See comment in header.
{
    assert(self.isActualRunLoopThread);
    assert(connection == self.connection);
    #pragma unused(connection)
    assert(error != nil);

    [self finishWithError:error];
}

@end

NSString * kQHTTPOperationErrorDomain = @"kQHTTPOperationErrorDomain";
