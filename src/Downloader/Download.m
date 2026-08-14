#import "Download.h"
#import <AVFoundation/AVFoundation.h>

@implementation SCIDownloadDelegate

- (instancetype)initWithAction:(DownloadAction)action showProgress:(BOOL)showProgress {
    self = [super init];
    
    if (self) {
        // Read-only properties
        _action = action;
        _showProgress = showProgress;

        // Properties
        self.downloadManager = [[SCIDownloadManager alloc] initWithDelegate:self];
        self.hud = [[JGProgressHUD alloc] init];
    }

    return self;
}
- (void)downloadFileWithURL:(NSURL *)url fileExtension:(NSString *)fileExtension hudLabel:(NSString *)hudLabel {
    // Show progress gui
    self.hud = [[JGProgressHUD alloc] init];
    self.hud.textLabel.text = hudLabel != nil ? hudLabel : @"Downloading";

    if (self.showProgress) {
        JGProgressHUDRingIndicatorView *indicatorView = [[JGProgressHUDRingIndicatorView alloc] init ];
        indicatorView.roundProgressLine = YES;
        indicatorView.ringWidth = 3.5;

        self.hud.indicatorView = indicatorView;
        self.hud.detailTextLabel.text = [NSString stringWithFormat:@"00%% Complete"];

        // Allow dismissing longer downloads (requiring progress updates)
        __weak typeof(self) weakSelf = self;
        self.hud.tapOutsideBlock = ^(JGProgressHUD * _Nonnull HUD) {
            [weakSelf.downloadManager cancelDownload];
        };
    }

    [self.hud showInView:topMostController().view];

    NSLog(@"[SCInsta] Download: Will start download for url \"%@\" with file extension: \".%@\"", url, fileExtension);

    // Start download using manager
    [self.downloadManager downloadFileWithURL:url fileExtension:fileExtension];
}

// Delegate methods
- (void)downloadDidStart {
    NSLog(@"[SCInsta] Download: Download started");
}
- (void)downloadDidCancel {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.hud dismiss];
    });

    NSLog(@"[SCInsta] Download: Download cancelled");
}
- (void)downloadDidProgress:(float)progress {
    NSLog(@"[SCInsta] Download: Download progress: %f", progress);
    
    if (self.showProgress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.hud setProgress:progress animated:false];
            self.hud.detailTextLabel.text = [NSString stringWithFormat:@"%02d%% Complete", (int)(progress * 100)];
        });
    }
}
- (void)downloadDidFinishWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Check if it actually errored (not cancelled)
        if (error && error.code != NSURLErrorCancelled) {
            NSLog(@"[SCInsta] Download: Download failed with error: \"%@\"", error);
            [SCIUtils showErrorHUDWithDescription:@"Error, try again later"];
        }
    });
}
- (void)downloadDidFinishWithFileURL:(NSURL *)fileURL {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.hud dismiss];

        NSLog(@"[SCInsta] Download: Download finished with url: \"%@\"", [fileURL absoluteString]);
        NSLog(@"[SCInsta] Download: Completed with action %d", (int)self.action);

        switch (self.action) {
            case share:
                [SCIUtils showShareVC:fileURL];
                break;
            
            case quickLook:
                [SCIUtils showQuickLookVC:@[fileURL]];
                break;

            case saveAudio:
                [self extractAudioFromVideo:fileURL];
                break;
        }
    });
}

// R6X9: Extract the audio track from a downloaded video and share it as an .m4a file
- (void)extractAudioFromVideo:(NSURL *)videoURL {
    JGProgressHUD *convertHud = [[JGProgressHUD alloc] init];
    convertHud.textLabel.text = @"Converting to audio";
    [convertHud showInView:topMostController().view];

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoURL options:nil];

    if ([[asset tracksWithMediaType:AVMediaTypeAudio] count] == 0) {
        [convertHud dismiss];
        [SCIUtils showErrorHUDWithDescription:@"This media has no audio track"];
        return;
    }

    NSString *cacheDirectoryPath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSURL *outputURL = [[NSURL fileURLWithPath:cacheDirectoryPath] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.m4a", NSUUID.UUID.UUIDString]];

    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    if (!exportSession) {
        [convertHud dismiss];
        [SCIUtils showErrorHUDWithDescription:@"Audio conversion not supported"];
        return;
    }

    exportSession.outputURL = outputURL;
    exportSession.outputFileType = AVFileTypeAppleM4A;

    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [convertHud dismiss];

            if (exportSession.status == AVAssetExportSessionStatusCompleted) {
                NSLog(@"[SCInsta] Audio export completed: %@", outputURL.absoluteString);
                [SCIUtils showShareVC:outputURL];
            }
            else {
                NSLog(@"[SCInsta] Audio export failed: %@", exportSession.error);
                [SCIUtils showErrorHUDWithDescription:@"Audio conversion failed"];
            }
        });
    }];
}

@end