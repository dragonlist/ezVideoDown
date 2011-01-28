/*
    File:       AppOptions.h
    Contains:   Option data for Video DL App 
    Written by: dragonlist 
    Copyright:  MIT 
*/
 
#import "AppOptions.h" 

@interface AppOptions: NSObject
{
    NSString *      _downloadDirPath;
    NSString *      _videoQuality;
}

- (id)initWithURL:(NSURL *)url videoDirPath:(NSString *)fileDirPath
{

}

@end
