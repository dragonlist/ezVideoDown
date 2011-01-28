/*
    File:       YouTubeVideo.h
    Contains:   Option data for Video DL App 
    Written by: dragonlist 
    Copyright:  MIT 
*/
 
#include <Foundation/Foundation.h>

@interface YouTubeVideo: NSObject
{
    NSString *      _downloadDirPath;
    NSString *      _videoQuality;
}

// Things that are configured by the init method and can't be changed.
@property (copy,   readwrite) NSString *    _downloadDirPath;
@property (copy,   readwrite) NSString *    _videoQuality;

@end
