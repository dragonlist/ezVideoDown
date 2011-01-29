 
#import "VideoDownloadOperation.h"
 
#include <fcntl.h>
#include <unistd.h>
 
@interface VideoDownloadOperation ()
 
// Read/write versions of public properties
 
@property (copy,   readwrite) NSString *    videoFilePath;
 
@end
 
@implementation VideoDownloadOperation
 
- (id)initWithURL:(NSURL *)url videosDirPath:(NSString *)videosDirPath depth:(NSUInteger)depth
    // See comment in header.
{
    assert(videosDirPath != nil);
    self = [super initWithURL:url];
    if (self != nil) {
        self->_videosDirPath = [videosDirPath copy];
        self->_depth = depth;
    }
    return self;
}
 
- (void)dealloc
{
    [self->_videoFilePath release];
    [self->_videosDirPath release];
    [super dealloc];
}
 
@synthesize videosDirPath = _videosDirPath;
@synthesize depth         = _depth;
 
@synthesize videoFilePath = _videoFilePath;
 
+ (NSString *)defaultExtensionToMIMEType:(NSString *)type
    // See comment in header.
{
    static NSDictionary *   sTypeToExtensionMap;
    
    // This needs to be thread safe because the client could start multiple 
    // download operations with different run loop threads and, if so, 
    // +defaultExtensionToMIMEType: can get call by multiple threads simultaneously.
    
    @synchronized (self) {
        if (sTypeToExtensionMap == nil) {
            sTypeToExtensionMap = [[NSDictionary alloc] initWithObjectsAndKeys:
                @"gif", @"video/gif", 
                @"png", @"video/png", 
                @"jpg", @"video/jpeg", 
                nil
            ];
            assert(sTypeToExtensionMap != nil);
        }
    }
    return (type == nil) ? nil : [sTypeToExtensionMap objectForKey:type];
}
 
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
    // An NSURLConnect delegate method.  We override this to set up a 
    // destination output stream for the incoming video data.
{
    [super connection:connection didReceiveResponse:response];
    
    // If the response is an error, no need to do anything special here. 
    // We only need to set up an output stream if we're successfully 
    // getting the video.
    
    if (self.isStatusCodeAcceptable) {
        NSString *  extension;
        NSString *  prefix;
        
        assert(self.responseOutputStream == nil);
        
        // Create a unique file for the downloaded video.  Start by getting an appropriate 
        // extension.  If we don't have one, that's bad.
        
        extension = [[self class] defaultExtensionToMIMEType:[self.lastResponse MIMEType]];
        if (extension != nil) {
            NSString *  fileName;
            NSString *  filePath;
            int         counter;
            int         fd;
            
            // Next calculate the file name prefix and extension.
            
            fileName = [self.lastResponse suggestedFilename];
            if (fileName == nil) {
                prefix = @"video";
                assert(extension != nil);       // that is, the default
            } else {
                if ([[fileName pathExtension] length] == 0) {
                    prefix = fileName;
                    assert(extension != nil);   // that is, the default
                } else {
                    prefix    = [fileName stringByDeletingPathExtension];
                    extension = [fileName pathExtension];
                }
            }
            assert(prefix != nil);
            assert(extension != nil);
            
            // Repeatedly try to create a new file with that info, adding a 
            // unique number if we get a conflict.
            
            counter = 0;
            filePath = [self.videosDirPath stringByAppendingPathComponent:[prefix stringByAppendingPathExtension:extension]];
            do {
                int     err;
                int     junk;
                
                err = 0;
                fd = open([filePath UTF8String], O_CREAT | O_EXCL | O_RDWR, 0666);
                if (fd < 0) {
                    err = errno;
                } else {
                    junk = close(fd);
                    assert(junk == 0);
                }
                
                if (err == 0) {
                    self.videoFilePath = filePath;
                    self.responseOutputStream = [NSOutputStream outputStreamToFileAtPath:filePath append:NO];
                    break;
                } else if (err == EEXIST) {
                    counter += 1;
                    if (counter > 500) {
                        break;
                    }
                    filePath = [self.videosDirPath stringByAppendingPathComponent:[[NSString stringWithFormat:@"%@-%d", prefix, counter] stringByAppendingPathExtension:extension]];
                } else if (err == EINTR) {
                    // do nothing
                } else {
                    break;
                }
            } while (YES);
        }
        
        // If we've failed to create a valid file, redirect the output to the bit bucket.
        
        if (self.responseOutputStream == nil) {
            self.responseOutputStream = [NSOutputStream outputStreamToFileAtPath:@"/dev/null" append:NO];
        }
    }
}
 
@end
