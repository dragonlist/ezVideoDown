/*
    File:       AppOptions.h
    Contains:   Option data for Video DL App 
    Written by: dragonlist 
    Copyright:  MIT 
*/
 

enum HTTPOperationState {
    kHTTPOperationStateInited, 
    kHTTPOperationStateExecuting, 
    kHTTPOperationStateFinished
};
typedef enum HTTPOperationState HTTPOperationState;

@interface HTTPOperation : NSOperation
{
    HTTPOperationState  _state;
    NSThread *              _HTTPThread;
    NSSet *                 _HTTPModes;
    NSError *               _error;

    NSURLRequest *      _request;
    NSIndexSet *        _acceptableStatusCodes;
    NSSet *             _acceptableContentTypes;
    NSOutputStream *    _responseOutputStream;
    NSUInteger          _defaultResponseSize;
    NSUInteger          _maximumResponseSize;
    NSURLConnection *   _connection;

    BOOL                _firstData;
    NSMutableData *     _dataAccumulator;
    NSURLRequest *      _lastRequest;
    NSHTTPURLResponse * _lastResponse;
    NSData *            _responseBody;

}

- (id)initWithRequest:(NSURLRequest *)request;      // designated
- (id)initWithURL:(NSURL *)url;                     // convenience, calls +[NSURLRequest requestWithURL:]

// Things that are configured by the init method and can't be changed.

@property (copy,   readonly)  NSURLRequest *        request;
@property (copy,   readonly)  NSURL *               URL;

// Things you can configure before queuing the operation.

// HTTPThread and HTTPModes inherited from QHTTPOperation
@property (copy,   readwrite) NSIndexSet *          acceptableStatusCodes;  // default is nil, implying 200..299
@property (copy,   readwrite) NSSet *               acceptableContentTypes; // default is nil, implying anything is acceptable

#if ! defined(NDEBUG)
@property (copy,   readwrite) NSError *             debugError;             // default is nil
@property (assign, readwrite) NSTimeInterval        debugDelay;             // default is none
#endif

// Things you can configure up to the point where you start receiving data. 
// Typically you would change these in -connection:didReceiveResponse:, but 
// it is possible to change them up to the point where -connection:didReceiveData: 
// is called for the first time (that is, you could override -connection:didReceiveData: 
// and change these before calling super).

// IMPORTANT: If you set a response stream, QHTTPOperation calls the response 
// stream synchronously.  This is fine for file and memory streams, but it would 
// not work well for other types of streams (like a bound pair).

@property (retain, readwrite) NSOutputStream *      responseOutputStream;   // defaults to nil, which puts response into responseBody
@property (assign, readwrite) NSUInteger            defaultResponseSize;    // default is 1 MB, ignored if responseOutputStream is set
@property (assign, readwrite) NSUInteger            maximumResponseSize;    // default is 4 MB, ignored if responseOutputStream is set
                                                                            // defaults are 1/4 of the above on embedded

// Things that are only meaningful after a response has been received;

@property (assign, readonly, getter=isStatusCodeAcceptable)  BOOL statusCodeAcceptable;
@property (assign, readonly, getter=isContentTypeAcceptable) BOOL contentTypeAcceptable;

// Things that are only meaningful after the operation is finished.

// error property inherited from QHTTPOperation
@property (copy,   readonly)  NSURLRequest *        lastRequest;       
@property (copy,   readonly)  NSHTTPURLResponse *   lastResponse;       

@property (copy,   readonly)  NSData *              responseBody;   


@end


@interface HTTPOperation (NSURLConnectionDelegate)

// QHTTPOperation implements all of these methods, so if you override them 
// you must consider whether or not to call super.
//
// These will be called on the operation's HTTP thread.

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace;
    // Routes the request to the authentication delegate if it exists, otherwise 
    // just returns NO.
    
- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
    // Routes the request to the authentication delegate if it exists, otherwise 
    // just cancels the challenge.

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response;
    // Latches the request and response in lastRequest and lastResponse.
    
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
    // Latches the response in lastResponse.
    
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data;
    // If this is the first chunk of data, it decides whether the data is going to be 
    // routed to memory (responseBody) or a stream (responseOutputStream) and makes the 
    // appropriate preparations.  For this and subsequent data it then actually shuffles 
    // the data to its destination.
    
- (void)connectionDidFinishLoading:(NSURLConnection *)connection;
    // Completes the operation with either no error (if the response status code is acceptable) 
    // or an error (otherwise).
    
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error;
    // Completes the operation with the error.

@end


