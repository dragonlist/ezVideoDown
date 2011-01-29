#import "HTTPOperation.h"
 
@interface VideoDownloadOperation : HTTPOperation
{
    NSString *      _videosDirPath;
    NSUInteger      _depth;
    NSString *      _videoFilePath;
}
 
+ (NSString *)defaultExtensionToMIMEType:(NSString *)type;
    // Returns a file extension appropriate for the specified video MIME type. 
    // This must return a non-nil value for the video to actually be downloaded. 
    // It currently handles GIF, PNG and JPEG.
 
- (id)initWithURL:(NSURL *)url videosDirPath:(NSString *)videosDirPath; 
    // Downloads the specific URL to a unique file within the specified 
    // directory.  depth is just along for the ride.
 
// Things that are configured by the init method and can't be changed.
 
@property (copy,   readonly ) NSString *    videosDirPath;
@property (assign, readonly ) NSUInteger    depth;
 
// Things that are only meaningful after the operation is finished.
 
@property (copy,   readonly ) NSString *    videoFilePath;
 
@end
