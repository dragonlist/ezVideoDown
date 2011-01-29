#import "BaseOperation.h"

@interface BaseOperation ()
 
// read/write versions of public properties
 
@property (assign, readwrite) BaseOperationState        state;
@property (copy,   readwrite) NSError *                 error;          
 
@end
 
@implementation BaseOperation
 
- (id)init
{
    self = [super init];
    if (self != nil) {
        assert(self->_state == kBaseOperationStateInited);
    }
    return self;
}
 
- (void)dealloc
{
    assert(self->_state != kBaseOperationStateExecuting);
    [self->_runLoopModes release];
    [self->_runLoopThread release];
    [self->_error release];
    [super dealloc];
}
 
#pragma mark * Properties
 
@synthesize runLoopThread = _runLoopThread;
@synthesize runLoopModes  = _runLoopModes;
 
- (NSThread *)actualBaseThread
    // Returns the effective run loop thread, that is, the one set by the user 
    // or, if that's not set, the main thread.
{
    NSThread *  result;
    
    result = self.runLoopThread;
    if (result == nil) {
        result = [NSThread mainThread];
    }
    return result;
}
 
- (BOOL)isActualBaseThread
    // Returns YES if the current thread is the actual run loop thread.
{
    return [[NSThread currentThread] isEqual:self.actualBaseThread];
}
 
- (NSSet *)actualBaseModes
{
    NSSet * result;
    
    result = self.runLoopModes;
    if ( (result == nil) || ([result count] == 0) ) {
        result = [NSSet setWithObject:NSDefaultRunLoopMode];
    }
    return result;
}
 
@synthesize error         = _error;
 
#pragma mark * Core state transitions
 
@synthesize state         = _state;
 
- (void)setState:(BaseOperationState)newState
    // Change the state of the operation, sending the appropriate KVO notifications.
{
    // any thread
 
    @synchronized (self) {
        BaseOperationState  oldState;
        
        // The following check is really important.  The state can only go forward, and there 
        // should be no redundant changes to the state (that is, newState must never be 
        // equal to self->_state).
        
        assert(newState > self->_state);
 
        // Transitions from executing to finished must be done on the run loop thread.
        
        assert( (newState != kBaseOperationStateFinished) || self.isActualBaseThread );
 
        // inited    + executing -> isExecuting
        // inited    + finished  -> isFinished
        // executing + finished  -> isExecuting + isFinished
 
        oldState = self->_state;
        if ( (newState == kBaseOperationStateExecuting) || (oldState == kBaseOperationStateExecuting) ) {
            [self willChangeValueForKey:@"isExecuting"];
        }
        if (newState == kBaseOperationStateFinished) {
            [self willChangeValueForKey:@"isFinished"];
        }
        self->_state = newState;
        if (newState == kBaseOperationStateFinished) {
            [self didChangeValueForKey:@"isFinished"];
        }
        if ( (newState == kBaseOperationStateExecuting) || (oldState == kBaseOperationStateExecuting) ) {
            [self didChangeValueForKey:@"isExecuting"];
        }
    }
}
 
- (void)startOnBaseThread
    // Starts the operation.  The actual -start method is very simple, 
    // deferring all of the work to be done on the run loop thread by this 
    // method.
{
    assert(self.isActualBaseThread);
    assert(self.state == kBaseOperationStateExecuting);
 
    if ([self isCancelled]) {
        
        // We were cancelled before we even got running.  Flip the the finished 
        // state immediately.
        
        [self finishWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
    } else {
        [self operationDidStart];
    }
}
 
- (void)cancelOnBaseThread
    // Cancels the operation.
{
    assert(self.isActualBaseThread);
 
    // We know that a) state was kBaseOperationStateExecuting when we were 
    // scheduled (that's enforced by -cancel), and b) the state can't go 
    // backwards (that's enforced by -setState), so we know the state must 
    // either be kBaseOperationStateExecuting or kBaseOperationStateFinished. 
    // We also know that the transition from executing to finished always 
    // happens on the run loop thread.  Thus, we don't need to lock here.  
    // We can look at state and, if we're executing, trigger a cancellation.
    
    if (self.state == kBaseOperationStateExecuting) {
        [self finishWithError:[NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError userInfo:nil]];
    }
}
 
- (void)finishWithError:(NSError *)error
{
    assert(self.isActualBaseThread);
    // error may be nil
 
    if (self.error == nil) {
        self.error = error;
    }
    [self operationWillFinish];
    self.state = kBaseOperationStateFinished;
}
 
#pragma mark * Subclass override points
 
- (void)operationDidStart
{
    assert(self.isActualBaseThread);
}
 
- (void)operationWillCancel
{
    assert(self.isActualBaseThread);
}
 
- (void)operationWillFinish
{
    assert(self.isActualBaseThread);
}
 
#pragma mark * Overrides
 
- (BOOL)isConcurrent
{
    // any thread
    return YES;
}
 
- (BOOL)isExecuting
{
    // any thread
    return self.state == kBaseOperationStateExecuting;
}
 
- (BOOL)isFinished
{
    // any thread
    return self.state == kBaseOperationStateFinished;
}
 
- (void)start
{
    // any thread
 
    assert(self.state == kBaseOperationStateInited);
    
    // We have to change the state here, otherwise isExecuting won't necessarily return 
    // true by the time we return from -start.  Also, we don't test for cancellation 
    // here because that would a) result in us sending isFinished notifications on a 
    // thread that isn't our run loop thread, and b) confuse the core cancellation code, 
    // which expects to run on our run loop thread.  Finally, we don't have to worry 
    // about races with other threads calling -start.  Only one thread is allowed to 
    // start us at a time.
    
    self.state = kBaseOperationStateExecuting;
    [self performSelector:@selector(startOnBaseThread) onThread:self.actualBaseThread withObject:nil waitUntilDone:NO modes:[self.actualBaseModes allObjects]];
}
 
- (void)cancel
{
    BOOL    runCancelOnBaseThread;
    BOOL    oldValue;
 
    // any thread
 
    // We need to synchronise here to avoid state changes to isCancelled and state
    // while we're running.
    
    @synchronized (self) {
        oldValue = [self isCancelled];
        
        // Call our super class so that isCancelled starts returning true immediately.
        
        [super cancel];
        
        // If we were the one to set isCancelled (that is, we won the race with regards 
        // other threads calling -cancel) and we're actually running (that is, we lost 
        // the race with other threads calling -start and the run loop thread finishing), 
        // we schedule to run on the run loop thread.
 
        runCancelOnBaseThread = ! oldValue && self.state == kBaseOperationStateExecuting;
    }
    if (runCancelOnBaseThread) {
        [self performSelector:@selector(cancelOnBaseThread) onThread:self.actualBaseThread withObject:nil waitUntilDone:YES modes:[self.actualBaseModes allObjects]];
    }
}
 
@end
