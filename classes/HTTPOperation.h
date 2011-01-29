/*
    File:       AppOptions.h
    Contains:   Option data for Video DL App 
    Written by: dragonlist 
    Copyright:  MIT 
*/

#import "BaseOperation.h"
 
@protocol HTTPOperationAuthenticationDelegate;
 
@interface HTTPOperation : BaseOperation /* <NSURLConnectionDelegate> */
{
    NSURLRequest *      _request;
    NSIndexSet *        _acceptableStatusCodes;
    NSSet *             _acceptableContentTypes;
    id<HTTPOperationAuthenticationDelegate>    _authenticationDelegate;
    NSOutputStream *    _responseOutputStream;
    NSUInteger          _defaultResponseSize;
    NSUInteger          _maximumResponseSize;
    NSURLConnection *   _connection;
    BOOL                _firstData;
    NSMutableData *     _dataAccumulator;
    NSURLRequest *      _lastRequest;
    NSHTTPURLResponse * _lastResponse;
    NSData *            _responseBody;
#if ! defined(NDEBUG)
    NSError *           _debugError;
    NSTimeInterval      _debugDelay;
    NSTimer *           _debugDelayTimer;
#endif
}
 
- (id)initWithRequest:(NSURLRequest *)request;      // designated
- (id)initWithURL:(NSURL *)url;                     // convenience, calls +[NSURLRequest requestWithURL:]
 
// Things that are configured by the init method and can't be changed.
 
@property (copy,   readonly)  NSURLRequest *        request;
@property (copy,   readonly)  NSURL *               URL;
 
// Things you can configure before queuing the operation.
 
// runLoopThread and runLoopModes inherited from BaseOperation
@property (copy,   readwrite) NSIndexSet *          acceptableStatusCodes;  // default is nil, implying 200..299
@property (copy,   readwrite) NSSet *               acceptableContentTypes; // default is nil, implying anything is acceptable
@property (assign, readwrite) id<HTTPOperationAuthenticationDelegate>  authenticationDelegate;
 
#if ! defined(NDEBUG)
@property (copy,   readwrite) NSError *             debugError;             // default is nil
@property (assign, readwrite) NSTimeInterval        debugDelay;             // default is none
#endif
 
// Things you can configure up to the point where you start receiving data. 
// Typically you would change these in -connection:didReceiveResponse:, but 
// it is possible to change them up to the point where -connection:didReceiveData: 
// is called for the first time (that is, you could override -connection:didReceiveData: 
// and change these before calling super).
 
// IMPORTANT: If you set a response stream, HTTPOperation calls the response 
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
 
// error property inherited from BaseOperation
@property (copy,   readonly)  NSURLRequest *        lastRequest;       
@property (copy,   readonly)  NSHTTPURLResponse *   lastResponse;       
 
@property (copy,   readonly)  NSData *              responseBody;   
 
@end
 
@interface HTTPOperation (NSURLConnectionDelegate)
 
// HTTPOperation implements all of these methods, so if you override them 
// you must consider whether or not to call super.
//
// These will be called on the operation's run loop thread.
 
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
 
@protocol HTTPOperationAuthenticationDelegate <NSObject>
@required
 
// These are called on the operation's run loop thread and have the same semantics as their 
// NSURLConnection equivalents.  It's important to realise that there is no 
// didCancelAuthenticationChallenge callback (because NSURLConnection doesn't issue one to us).  
// Rather, an authentication delegate is expected to observe the operation and cancel itself 
// if the operation completes while the challenge is running.
 
- (BOOL)httpOperation:(HTTPOperation *)operation canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace;
- (void)httpOperation:(HTTPOperation *)operation didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
 
@end
 
extern NSString * kHTTPOperationErrorDomain;
 
// positive error codes are HTML status codes (when they are not allowed via acceptableStatusCodes)
//
// 0 is, of course, not a valid error code
//
// negative error codes are errors from the module
 
enum {
    kHTTPOperationErrorResponseTooLarge = -1, 
    kHTTPOperationErrorOnOutputStream   = -2, 
    kHTTPOperationErrorBadContentType   = -3
};

