#import <Foundation/Foundation.h>
 
enum BaseOperationState {
    kBaseOperationStateInited, 
    kBaseOperationStateExecuting, 
    kBaseOperationStateFinished
};
typedef enum BaseOperationState BaseOperationState;
 
@interface BaseOperation : NSOperation
{
    BaseOperationState      _state;
    NSThread *              _runLoopThread;
    NSSet *                 _runLoopModes;
    NSError *               _error;
}
 
// Things you can configure before queuing the operation.
 
// IMPORTANT: Do not change these after queuing the operation; it's very likely that 
// bad things will happen if you do.
 
@property (retain, readwrite) NSThread *                runLoopThread;          // default is nil, implying main thread
@property (copy,   readwrite) NSSet *                   runLoopModes;           // default is nil, implying set containing NSDefaultBaseMode
 
// Things that are only meaningful after the operation is finished.
 
@property (copy,   readonly ) NSError *                 error;
 
// Things you can only alter implicitly.
 
@property (assign, readonly ) BaseOperationState        state;
@property (retain, readonly ) NSThread *                actualBaseThread;    // main thread if runLoopThread is nil, runLoopThread otherwise
@property (assign, readonly ) BOOL                      isActualBaseThread;  // YES if the current thread is the actual run loop thread
@property (copy,   readonly ) NSSet *                   actualBaseModes;     // set containing NSDefaultBaseMode if runLoopModes is nil or empty, runLoopModes otherwise
 
@end
 
@interface BaseOperation (SubClassSupport)
 
// Override points
 
// A subclass will probably need to override -operationDidStart and -operationWillFinish 
// to set up and tear down its run loop sources, respectively.  These are always called 
// on the actual run loop thread.
//
// Note that -operationWillFinish will be called even if the operation is cancelled. 
// -operationWillCancel is only needed if you want to perform different behaviour that's 
// specific to cancellation.
//
// -operationWillFinish can check the error property to see whether the operation was 
// successful.  error will be NSCocoaErrorDomain/NSUserCancelledError on cancellation. 
//
// -operationDidStart is allowed to call -finishWithError:.
 
- (void)operationDidStart;
- (void)operationWillCancel;
- (void)operationWillFinish;
 
// Support methods
 
// A subclass should call finishWithError: when the operation is complete, passing nil 
// for no error and an error otherwise.  It must call this on the actual run loop thread. 
// 
// Note that this will call -operationWillFinish before returning.
 
- (void)finishWithError:(NSError *)error;
 
@end
