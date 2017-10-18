//
//  FileDownloaderDelegate.m
//  FileDownloader
//
//  Created by Ossey on 2017/7/3.
//  Copyright © 2017年 Ossey. All rights reserved.
//

#import "FileDownloaderDelegate.h"
#import "UIApplication+ActivityIndicator.h"
#import "FileDownloaderModule.h"
#import "FileDownloadProgress.h"
#import "FileItem.h"
#import "FileDownloadConst.h"

#define dispatch_main_async_safe(block)\
if (strcmp(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), dispatch_queue_get_label(dispatch_get_main_queue())) == 0) {\
block();\
} else {\
dispatch_async(dispatch_get_main_queue(), block);\
}




@interface FileDownloaderDelegate ()

@end

@implementation FileDownloaderDelegate



////////////////////////////////////////////////////////////////////////
#pragma mark - FileDownloaderDelegate
////////////////////////////////////////////////////////////////////////

- (void)downloadSuccessnWithDownloadItem:(id<FileDownloadOperation>)downloadItem {
    
    // 根据aIdentifier在downloadItems中查找对应的DownloadItem，更改其下载状态，发送通知
    NSUInteger foundItemIdx = [self foundItemIndxInDownloadItemsByURL:downloadItem.urlPath];
    FileItem *fileItem = nil;
    if (foundItemIdx != NSNotFound) {
        DLog(@"INFO: Download success (id: %@)", downloadItem.urlPath);
        
        fileItem = [[FileDownloaderModule sharedInstance].downloadItems objectAtIndex:foundItemIdx];
        fileItem.status = FileDownloadStatusSuccess;
        fileItem.localFolderURL = downloadItem.localFolderURL;
        fileItem.MIMEType = downloadItem.MIMEType;
        [[FileDownloaderModule sharedInstance] storedDownloadItems];
    } else {
        DLog(@"Error: Completed download item not found (id: %@)", downloadItem.urlPath);
    }
    dispatch_main_async_safe(^{
        [[NSNotificationCenter defaultCenter] postNotificationName:FileDownloadSussessNotification object:downloadItem];
    })
}

- (void)downloadFailureWithDownloadItem:(id<FileDownloadOperation>)downloadItem
                                  error:(NSError *)error {
    
    // 根据aIdentifier在downloadItems中查找对应的DownloadItem
    NSUInteger foundItemIdx = [self foundItemIndxInDownloadItemsByURL:downloadItem.urlPath];
     FileItem *fileItem = nil;
    if (foundItemIdx != NSNotFound) {
        fileItem = [[FileDownloaderModule sharedInstance].downloadItems objectAtIndex:foundItemIdx];
        fileItem.lastHttpStatusCode = downloadItem.lastHttpStatusCode;
        fileItem.downloadError = error;
        fileItem.errorMessagesStack = downloadItem.errorMessagesStack;
        fileItem.localFolderURL = downloadItem.localFolderURL;
        // 更新此下载失败的item的状态
        if (fileItem.status != FileDownloadStatusPaused) {
            if ([error.domain isEqualToString:NSURLErrorDomain] &&
                (error.code == NSURLErrorCancelled)) {
                fileItem.status = FileDownloadStatusNotStarted;
            } else {
                fileItem.status = FileDownloadStatusFailure;
            }
        }
        [[FileDownloaderModule sharedInstance] storedDownloadItems];
        
    }
    dispatch_main_async_safe(^{
        // 发送失败通知
        [[NSNotificationCenter defaultCenter] postNotificationName:FileDownloadFailureNotification object:downloadItem];
    })
}

- (void)downloadTaskWillBeginWithDownloadItem:(id<FileDownloadOperation>)downloadItem {
    [self toggleNetworkActivityIndicatorVisible:YES];
    NSUInteger foundItemIdx = [self foundItemIndxInDownloadItemsByURL:downloadItem.urlPath];
     FileItem *fileItem = nil;
    if (foundItemIdx != NSNotFound) {
        fileItem = [[FileDownloaderModule sharedInstance].downloadItems objectAtIndex:foundItemIdx];
        fileItem.status = FileDownloadStatusDownloading;
        if (!fileItem.localFolderURL) {
            fileItem.localFolderURL = downloadItem.localFolderURL;
        }
    }
    [[FileDownloaderModule sharedInstance] storedDownloadItems];
}

- (void)downloadTaskDidEndWithDownloadItem:(id<FileDownloadOperation>)downloadItem {
    [self toggleNetworkActivityIndicatorVisible:NO];
    dispatch_main_async_safe(^{
        // 发送失败通知
        [[NSNotificationCenter defaultCenter] postNotificationName:FileDownloadStartedNotification object:downloadItem];
    })
}

- (void)downloadProgressChangeWithURL:(NSString *)url progress:(FileDownloadProgress *)progress {
    
    NSUInteger foundItemIdx = [self foundItemIndxInDownloadItemsByURL:url];
    
     FileItem *downloadItem = nil;
    if (foundItemIdx != NSNotFound) {
        downloadItem = [[FileDownloaderModule sharedInstance].downloadItems objectAtIndex:foundItemIdx];
        if (progress) {
            downloadItem.progressObj = progress;
            downloadItem.progressObj.lastLocalizedDescription = downloadItem.progressObj.nativeProgress.localizedDescription;
            downloadItem.progressObj.lastLocalizedAdditionalDescription = downloadItem.progressObj.nativeProgress.localizedAdditionalDescription;
            progress.progressHandler = downloadItem.progressHandler;
        }
    }
    [[FileDownloaderModule sharedInstance] storedDownloadItems];
    dispatch_main_async_safe(^{
        [[NSNotificationCenter defaultCenter] postNotificationName:FileDownloadProgressChangeNotification object:downloadItem];
    })
    
}

- (void)downloadPausedWithURL:(NSString *)url {
    
    NSUInteger foundItemIdx = [self foundItemIndxInDownloadItemsByURL:url];
    
    if (foundItemIdx != NSNotFound) {
        DLog(@"INFO: Download paused - id: %@", url);
        
         FileItem *downloadItem = [[FileDownloaderModule sharedInstance].downloadItems objectAtIndex:foundItemIdx];
        downloadItem.status = FileDownloadStatusPaused;
        [[FileDownloaderModule sharedInstance] storedDownloadItems];
    } else {
        DLog(@"Error: Paused download item not found (id: %@)", url);
    }
}

- (void)downloadResumeDownloadWithURL:(NSString *)url {
    
    [[FileDownloaderModule sharedInstance] start:url];
}

- (BOOL)downloadLocalFolderURL:(NSURL *)aLocalFileURL isVaildByURL:(NSString *)url {
    
    // 检测文件大小,项目中有时需要检测下载的文件的类型是否相匹配，这里就仅仅检测文件大小
    // 根据文件的大小判断下载的文件是否有效,比如可以设定当文件超过多少kb就视为无效
    BOOL isValid = YES;
    
    NSError *error = nil;
    NSDictionary *fileAttritubes = [[NSFileManager defaultManager] attributesOfItemAtPath:aLocalFileURL.path error:&error];
    
    if (error) {
        DLog(@"Error: Error on getting file size for item at %@: %@", aLocalFileURL, error.localizedDescription);
        isValid = NO;
    } else {
        unsigned long long fileSize = [fileAttritubes fileSize];
        if (fileSize == 0) {
            isValid = NO;
        }
    }
    return isValid;
}


/// 一个任务进入等待时调用
- (void)downloadDidWaitingWithURLPath:(NSString *)url progress:(FileDownloadProgress *)progress {
    NSUInteger foundItemIdx = [self foundItemIndxInDownloadItemsByURL:url];
    
     FileItem *downloadItem = nil;
    if (foundItemIdx != NSNotFound) {
        downloadItem = [[FileDownloaderModule sharedInstance].downloadItems objectAtIndex:foundItemIdx];
        downloadItem.status = FileDownloadStatusWaiting;
        if (progress) {
            downloadItem.progressObj = progress;
            downloadItem.progressObj.lastLocalizedDescription = downloadItem.progressObj.nativeProgress.localizedDescription;
            downloadItem.progressObj.lastLocalizedAdditionalDescription = downloadItem.progressObj.nativeProgress.localizedAdditionalDescription;
        }
    }
    
    dispatch_main_async_safe(^{
        [[NSNotificationCenter defaultCenter] postNotificationName:FileDownloadWaittingNotification object:downloadItem];
    })
}

/// 从等待队列中开始下载一个任务
- (void)downloadStartFromWaitingQueueWithURLPath:(NSString *)url progress:(FileDownloadProgress *)progress {
    NSUInteger foundItemIdx = [self foundItemIndxInDownloadItemsByURL:url];
    
     FileItem *downloadItem = nil;
    if (foundItemIdx != NSNotFound) {
        downloadItem = [[FileDownloaderModule sharedInstance].downloadItems objectAtIndex:foundItemIdx];
        if (progress) {
            downloadItem.progressObj = progress;
            downloadItem.progressObj.lastLocalizedDescription = downloadItem.progressObj.nativeProgress.localizedDescription;
            downloadItem.progressObj.lastLocalizedAdditionalDescription = downloadItem.progressObj.nativeProgress.localizedAdditionalDescription;
        }
    }
}

- (NSURL *)localFolderURLWithRemoteURL:(NSURL *)remoteURL {
    NSString *documentPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSURL *folderURL = [NSURL fileURLWithPath:documentPath];
    return folderURL;
}

////////////////////////////////////////////////////////////////////////
#pragma mark - Other
////////////////////////////////////////////////////////////////////////

// 查找数组中第一个符合条件的对象（代码块过滤），返回对应索引
// 查找urlPath在downloadItems中对应的FileDownloadOperation的索引
- (NSUInteger)foundItemIndxInDownloadItemsByURL:(NSString *)urlPath {
    if (!urlPath.length) {
        return NSNotFound;
    }
    return [[FileDownloaderModule sharedInstance].downloadItems indexOfObjectPassingTest:
            ^BOOL(FileItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                return [urlPath isEqualToString:obj.urlPath];
            }];
}


- (void)toggleNetworkActivityIndicatorVisible:(BOOL)visible {
    if (visible) {
        [[UIApplication sharedApplication] retainNetworkActivityIndicator];
    } else {
        [[UIApplication sharedApplication] releaseNetworkActivityIndicator];
    }
}




@end