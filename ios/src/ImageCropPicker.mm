//
//  ImageManager.m
//
//  Created by Ivan Pusic on 5/4/16.
//  Copyright © 2016 Facebook. All rights reserved.
//

#import <MobileCoreServices/MobileCoreServices.h>

#import "ImageCropPicker.h"
#ifdef RCT_NEW_ARCH_ENABLED
#import <RNCImageCropPickerSpec/RNCImageCropPickerSpec.h>
#endif

#define ERROR_PICKER_CANNOT_RUN_CAMERA_ON_SIMULATOR_KEY @"E_PICKER_CANNOT_RUN_CAMERA_ON_SIMULATOR"
#define ERROR_PICKER_CANNOT_RUN_CAMERA_ON_SIMULATOR_MSG @"Cannot run camera on simulator"

#define ERROR_NO_CAMERA_PERMISSION_KEY @"E_NO_CAMERA_PERMISSION"
#define ERROR_NO_CAMERA_PERMISSION_MSG @"User did not grant camera permission."

#define ERROR_NO_LIBRARY_PERMISSION_KEY @"E_NO_LIBRARY_PERMISSION"
#define ERROR_NO_LIBRARY_PERMISSION_MSG @"User did not grant library permission."

#define ERROR_PICKER_CANCEL_KEY @"E_PICKER_CANCELLED"
#define ERROR_PICKER_CANCEL_MSG @"User cancelled image selection"

#define ERROR_PICKER_NO_DATA_KEY @"E_NO_IMAGE_DATA_FOUND"
#define ERROR_PICKER_NO_DATA_MSG @"Cannot find image data"

#define ERROR_CROPPER_IMAGE_NOT_FOUND_KEY @"E_CROPPER_IMAGE_NOT_FOUND"
#define ERROR_CROPPER_IMAGE_NOT_FOUND_MSG @"Can't find the image at the specified path"

#define ERROR_CLEANUP_ERROR_KEY @"E_ERROR_WHILE_CLEANING_FILES"
#define ERROR_CLEANUP_ERROR_MSG @"Error while cleaning up tmp files"

#define ERROR_CANNOT_SAVE_IMAGE_KEY @"E_CANNOT_SAVE_IMAGE"
#define ERROR_CANNOT_SAVE_IMAGE_MSG @"Cannot save image. Unable to write to tmp location."

#define ERROR_CANNOT_PROCESS_VIDEO_KEY @"E_CANNOT_PROCESS_VIDEO"
#define ERROR_CANNOT_PROCESS_VIDEO_MSG @"Cannot process video data"

@implementation ImageResult
@end

@implementation ImageCropPicker

RCT_EXPORT_MODULE(RNCImageCropPicker);

@synthesize bridge = _bridge;

- (instancetype)init
{
    if (self = [super init]) {
        self.defaultOptions = @{
            @"multiple": @NO,
            @"cropping": @NO,
            @"cropperCircleOverlay": @NO,
            @"writeTempFile": @YES,
            @"includeBase64": @NO,
            @"includeExif": @NO,
            @"compressVideo": @YES,
            @"minFiles": @1,
            @"maxFiles": @5,
            @"width": @200,
            @"waitAnimationEnd": @YES,
            @"height": @200,
            @"useFrontCamera": @NO,
            @"avoidEmptySpaceAroundImage": @YES,
            @"compressImageQuality": @0.8,
            @"compressVideoPreset": @"MediumQuality",
            @"loadingLabelText": @"Processing assets...",
            @"mediaType": @"any",
            @"showsSelectedCount": @YES,
            @"forceJpg": @NO,
            @"sortOrder": @"none",
            @"cropperCancelText": @"Cancel",
            @"cropperChooseText": @"Choose",
            @"cropperRotateButtonsHidden": @NO
        };
        self.compression = [[Compression alloc] init];
    }
    
    return self;
}

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

- (void (^ __nullable)(void))waitAnimationEnd:(void (^ __nullable)(void))completion {
    if ([[self.options objectForKey:@"waitAnimationEnd"] boolValue]) {
        return completion;
    }
    
    if (completion != nil) {
        completion();
    }
    
    return nil;
}

- (void)checkCameraPermissions:(void(^)(BOOL granted))callback
{
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        callback(YES);
        return;
    } else if (status == AVAuthorizationStatusNotDetermined){
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            callback(granted);
            return;
        }];
    } else {
        callback(NO);
    }
}

- (void) setConfiguration:(NSDictionary *)options
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject {
    
    self.resolve = resolve;
    self.reject = reject;
    self.options = [NSMutableDictionary dictionaryWithDictionary:self.defaultOptions];
    for (NSString *key in options.keyEnumerator) {
        [self.options setValue:options[key] forKey:key];
    }
}

- (UIViewController*) getRootVC {
    UIViewController *root = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
    while (root.presentedViewController != nil) {
        root = root.presentedViewController;
    }
    
    return root;
}

RCT_EXPORT_METHOD(openCamera:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    [self setConfiguration:options resolver:resolve rejecter:reject];
    self.currentSelectionMode = CAMERA;
    
#if TARGET_IPHONE_SIMULATOR
    self.reject(ERROR_PICKER_CANNOT_RUN_CAMERA_ON_SIMULATOR_KEY, ERROR_PICKER_CANNOT_RUN_CAMERA_ON_SIMULATOR_MSG, nil);
    return;
#else
    [self checkCameraPermissions:^(BOOL granted) {
        if (!granted) {
            self.reject(ERROR_NO_CAMERA_PERMISSION_KEY, ERROR_NO_CAMERA_PERMISSION_MSG, nil);
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            UIImagePickerController *picker = [[UIImagePickerController alloc] init];
            picker.delegate = self;
            picker.allowsEditing = NO;
            picker.sourceType = UIImagePickerControllerSourceTypeCamera;
            
            NSString *mediaType = [self.options objectForKey:@"mediaType"];
            
            if ([mediaType isEqualToString:@"video"]) {
                NSArray *availableTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
                
                if ([availableTypes containsObject:(NSString *)kUTTypeMovie]) {
                    picker.mediaTypes = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeMovie, nil];
                    picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
                }
            }
            
            if ([[self.options objectForKey:@"useFrontCamera"] boolValue]) {
                picker.cameraDevice = UIImagePickerControllerCameraDeviceFront;
            }
            
            [[self getRootVC] presentViewController:picker animated:YES completion:nil];
        });
    }];
#endif
}

- (void)viewDidLoad {
    [self viewDidLoad];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    NSString* mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    
    if (CFStringCompare ((__bridge CFStringRef) mediaType, kUTTypeMovie, 0) == kCFCompareEqualTo) {
        NSURL *url = [info objectForKey:UIImagePickerControllerMediaURL];
        AVURLAsset *asset = [AVURLAsset assetWithURL:url];
        NSString *fileName = [[asset.URL path] lastPathComponent];
        
        [self handleVideo:asset
             withFileName:fileName
      withLocalIdentifier:nil
               completion:^(NSDictionary* video) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (video == nil) {
                    [picker dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                        self.reject(ERROR_CANNOT_PROCESS_VIDEO_KEY, ERROR_CANNOT_PROCESS_VIDEO_MSG, nil);
                    }]];
                    return;
                }
                
                [picker dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                    self.resolve(video);
                }]];
            });
        }
         ];
    } else {
        UIImage *chosenImage = [info objectForKey:UIImagePickerControllerOriginalImage];
        
        NSDictionary *exif;
        if([[self.options objectForKey:@"includeExif"] boolValue]) {
            exif = [info objectForKey:UIImagePickerControllerMediaMetadata];
        }
        
        [self processSingleImagePick:chosenImage withExif:exif withViewController:picker withSourceURL:self.croppingFile[@"sourceURL"] withLocalIdentifier:self.croppingFile[@"localIdentifier"] withFilename:self.croppingFile[@"filename"] withCreationDate:self.croppingFile[@"creationDate"] withModificationDate:self.croppingFile[@"modificationDate"]];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
        self.reject(ERROR_PICKER_CANCEL_KEY, ERROR_PICKER_CANCEL_MSG, nil);
    }]];
}

- (NSString*) getTmpDirectory {
    NSString *TMP_DIRECTORY = @"react-native-image-crop-picker/";
    NSString *tmpFullPath = [NSTemporaryDirectory() stringByAppendingString:TMP_DIRECTORY];
    
    BOOL isDir;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:tmpFullPath isDirectory:&isDir];
    if (!exists) {
        [[NSFileManager defaultManager] createDirectoryAtPath: tmpFullPath
                                  withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return tmpFullPath;
}

- (BOOL)cleanTmpDirectory {
    NSString* tmpDirectoryPath = [self getTmpDirectory];
    NSArray* tmpDirectory = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmpDirectoryPath error:NULL];
    
    for (NSString *file in tmpDirectory) {
        BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@%@", tmpDirectoryPath, file] error:NULL];
        
        if (!deleted) {
            return NO;
        }
    }
    
    return YES;
}

RCT_EXPORT_METHOD(cleanSingle:(NSString *) path
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    
    if (!deleted) {
        reject(ERROR_CLEANUP_ERROR_KEY, ERROR_CLEANUP_ERROR_MSG, nil);
    } else {
        resolve(nil);
    }
}

RCT_REMAP_METHOD(clean, resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    if (![self cleanTmpDirectory]) {
        reject(ERROR_CLEANUP_ERROR_KEY, ERROR_CLEANUP_ERROR_MSG, nil);
    } else {
        resolve(nil);
    }
}

RCT_EXPORT_METHOD(openPicker:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    [self setConfiguration:options resolver:resolve rejecter:reject];
    self.currentSelectionMode = PICKER;
    
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            self.reject(ERROR_NO_LIBRARY_PERMISSION_KEY, ERROR_NO_LIBRARY_PERMISSION_MSG, nil);
            return;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // init picker
            QBImagePickerController *imagePickerController =
            [QBImagePickerController new];
            imagePickerController.delegate = self;
            imagePickerController.allowsMultipleSelection = [[self.options objectForKey:@"multiple"] boolValue];
            imagePickerController.minimumNumberOfSelection = abs([[self.options objectForKey:@"minFiles"] intValue]);
            imagePickerController.maximumNumberOfSelection = abs([[self.options objectForKey:@"maxFiles"] intValue]);
            imagePickerController.showsNumberOfSelectedAssets = [[self.options objectForKey:@"showsSelectedCount"] boolValue];
            imagePickerController.sortOrder = [self.options objectForKey:@"sortOrder"];
            
            NSArray *smartAlbums = [self.options objectForKey:@"smartAlbums"];
            if (smartAlbums != nil) {
                NSDictionary *albums = @{
                    //user albums
                    @"Regular" : @(PHAssetCollectionSubtypeAlbumRegular),
                    @"SyncedEvent" : @(PHAssetCollectionSubtypeAlbumSyncedEvent),
                    @"SyncedFaces" : @(PHAssetCollectionSubtypeAlbumSyncedFaces),
                    @"SyncedAlbum" : @(PHAssetCollectionSubtypeAlbumSyncedAlbum),
                    @"Imported" : @(PHAssetCollectionSubtypeAlbumImported),
                    
                    //cloud albums
                    @"PhotoStream" : @(PHAssetCollectionSubtypeAlbumMyPhotoStream),
                    @"CloudShared" : @(PHAssetCollectionSubtypeAlbumCloudShared),
                    
                    //smart albums
                    @"Generic" : @(PHAssetCollectionSubtypeSmartAlbumGeneric),
                    @"Panoramas" : @(PHAssetCollectionSubtypeSmartAlbumPanoramas),
                    @"Videos" : @(PHAssetCollectionSubtypeSmartAlbumVideos),
                    @"Favorites" : @(PHAssetCollectionSubtypeSmartAlbumFavorites),
                    @"Timelapses" : @(PHAssetCollectionSubtypeSmartAlbumTimelapses),
                    @"AllHidden" : @(PHAssetCollectionSubtypeSmartAlbumAllHidden),
                    @"RecentlyAdded" : @(PHAssetCollectionSubtypeSmartAlbumRecentlyAdded),
                    @"Bursts" : @(PHAssetCollectionSubtypeSmartAlbumBursts),
                    @"SlomoVideos" : @(PHAssetCollectionSubtypeSmartAlbumSlomoVideos),
                    @"UserLibrary" : @(PHAssetCollectionSubtypeSmartAlbumUserLibrary),
                    @"SelfPortraits" : @(PHAssetCollectionSubtypeSmartAlbumSelfPortraits),
                    @"Screenshots" : @(PHAssetCollectionSubtypeSmartAlbumScreenshots),
                    @"DepthEffect" : @(PHAssetCollectionSubtypeSmartAlbumDepthEffect),
                    @"LivePhotos" : @(PHAssetCollectionSubtypeSmartAlbumLivePhotos),
                    @"Animated" : @(PHAssetCollectionSubtypeSmartAlbumAnimated),
                    @"LongExposure" : @(PHAssetCollectionSubtypeSmartAlbumLongExposures),
                };
                
                NSMutableArray *albumsToShow = [NSMutableArray arrayWithCapacity:smartAlbums.count];
                for (NSString* smartAlbum in smartAlbums) {
                    if ([albums objectForKey:smartAlbum] != nil) {
                        [albumsToShow addObject:[albums objectForKey:smartAlbum]];
                    }
                }
                imagePickerController.assetCollectionSubtypes = albumsToShow;
            }
            
            if ([[self.options objectForKey:@"cropping"] boolValue]) {
                imagePickerController.mediaType = QBImagePickerMediaTypeImage;
            } else {
                NSString *mediaType = [self.options objectForKey:@"mediaType"];
                
                if ([mediaType isEqualToString:@"photo"]) {
                    imagePickerController.mediaType = QBImagePickerMediaTypeImage;
                } else if ([mediaType isEqualToString:@"video"]) {
                    imagePickerController.mediaType = QBImagePickerMediaTypeVideo;
                } else {
                    imagePickerController.mediaType = QBImagePickerMediaTypeAny;
                }
            }
            
            [imagePickerController setModalPresentationStyle: UIModalPresentationFullScreen];
            [[self getRootVC] presentViewController:imagePickerController animated:YES completion:nil];
        });
    }];
}

RCT_EXPORT_METHOD(openCropper:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    [self setConfiguration:options resolver:resolve rejecter:reject];
    self.currentSelectionMode = CROPPING;
    
    NSString *path = [options objectForKey:@"path"];
    
    [[self.bridge moduleForName:@"ImageLoader" lazilyLoadIfNecessary:YES] loadImageWithURLRequest:[RCTConvert NSURLRequest:path] callback:^(NSError *error, UIImage *image) {
        if (error) {
            self.reject(ERROR_CROPPER_IMAGE_NOT_FOUND_KEY, ERROR_CROPPER_IMAGE_NOT_FOUND_MSG, nil);
        } else {
            [self cropImage:[image fixOrientation]];
        }
    }];
}

- (void)showActivityIndicator:(void (^)(UIActivityIndicatorView*, UIView*))handler {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *mainView = [[self getRootVC] view];
        
        // create overlay
        UIView *loadingView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
        loadingView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5];
        loadingView.clipsToBounds = YES;
        
        // create loading spinner
        UIActivityIndicatorView *activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        activityView.frame = CGRectMake(65, 40, activityView.bounds.size.width, activityView.bounds.size.height);
        activityView.center = loadingView.center;
        [loadingView addSubview:activityView];
        
        // create message
        UILabel *loadingLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 115, 130, 22)];
        loadingLabel.backgroundColor = [UIColor clearColor];
        loadingLabel.textColor = [UIColor whiteColor];
        loadingLabel.adjustsFontSizeToFitWidth = YES;
        CGPoint loadingLabelLocation = loadingView.center;
        loadingLabelLocation.y += [activityView bounds].size.height;
        loadingLabel.center = loadingLabelLocation;
        loadingLabel.textAlignment = NSTextAlignmentCenter;
        loadingLabel.text = [self.options objectForKey:@"loadingLabelText"];
        [loadingLabel setFont:[UIFont boldSystemFontOfSize:18]];
        [loadingView addSubview:loadingLabel];
        
        // show all
        [mainView addSubview:loadingView];
        [activityView startAnimating];
        
        handler(activityView, loadingView);
    });
}

- (void) handleVideo:(AVAsset*)asset withFileName:(NSString*)fileName withLocalIdentifier:(NSString*)localIdentifier completion:(void (^)(NSDictionary* image))completion {
    NSURL *sourceURL = [(AVURLAsset *)asset URL];
    
    // create temp file
    NSString *tmpDirFullPath = [self getTmpDirectory];
    NSString *filePath = [tmpDirFullPath stringByAppendingString:[[NSUUID UUID] UUIDString]];
    filePath = [filePath stringByAppendingString:@".mp4"];
    NSURL *outputURL = [NSURL fileURLWithPath:filePath];
    
    [self.compression compressVideo:sourceURL outputURL:outputURL withOptions:self.options handler:^(AVAssetExportSession *exportSession) {
        if (exportSession.status == AVAssetExportSessionStatusCompleted) {
            AVAsset *compressedAsset = [AVAsset assetWithURL:outputURL];
            AVAssetTrack *track = [[compressedAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
            
            NSNumber *fileSizeValue = nil;
            [outputURL getResourceValue:&fileSizeValue
                                 forKey:NSURLFileSizeKey
                                  error:nil];
            
            AVURLAsset *durationFromUrl = [AVURLAsset assetWithURL:outputURL];
            CMTime time = [durationFromUrl duration];
            int milliseconds = ceil(time.value/time.timescale) * 1000;
            
            completion([self createAttachmentResponse:[outputURL absoluteString]
                                             withExif:nil
                                        withSourceURL:[sourceURL absoluteString]
                                  withLocalIdentifier:localIdentifier
                                         withFilename:fileName
                                            withWidth:[NSNumber numberWithFloat:track.naturalSize.width]
                                           withHeight:[NSNumber numberWithFloat:track.naturalSize.height]
                                             withMime:@"video/mp4"
                                             withSize:fileSizeValue
                                         withDuration:[NSNumber numberWithFloat:milliseconds]
                                             withData:nil
                                             withRect:CGRectNull
                                     withCreationDate:nil
                                 withModificationDate:nil
                        ]);
        } else {
            completion(nil);
        }
    }];
}

- (void) getVideoAsset:(PHAsset*)forAsset completion:(void (^)(NSDictionary* image))completion {
    PHImageManager *manager = [PHImageManager defaultManager];
    PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
    options.version = PHVideoRequestOptionsVersionCurrent;
    options.networkAccessAllowed = YES;
    options.deliveryMode = PHVideoRequestOptionsDeliveryModeHighQualityFormat;
    
    [manager
     requestAVAssetForVideo:forAsset
     options:options
     resultHandler:^(AVAsset * asset, AVAudioMix * audioMix,
                     NSDictionary *info) {
        [self handleVideo:asset
             withFileName:[forAsset valueForKey:@"filename"]
      withLocalIdentifier:forAsset.localIdentifier
               completion:completion
         ];
    }];
}

- (NSDictionary*) createAttachmentResponse:(NSString*)filePath withExif:(NSDictionary*) exif withSourceURL:(NSString*)sourceURL withLocalIdentifier:(NSString*)localIdentifier withFilename:(NSString*)filename withWidth:(NSNumber*)width withHeight:(NSNumber*)height withMime:(NSString*)mime withSize:(NSNumber*)size withDuration:(NSNumber*)duration withData:(NSString*)data withRect:(CGRect)cropRect withCreationDate:(NSDate*)creationDate withModificationDate:(NSDate*)modificationDate {
    return @{
        @"path": (filePath && ![filePath isEqualToString:(@"")]) ? filePath : [NSNull null],
        @"sourceURL": (sourceURL) ? sourceURL : [NSNull null],
        @"localIdentifier": (localIdentifier) ? localIdentifier : [NSNull null],
        @"filename": (filename) ? filename : [NSNull null],
        @"width": width,
        @"height": height,
        @"mime": mime,
        @"size": size,
        @"data": (data) ? data : [NSNull null],
        @"exif": (exif) ? exif : [NSNull null],
        @"cropRect": CGRectIsNull(cropRect) ? [NSNull null] : [ImageCropPicker cgRectToDictionary:cropRect],
        @"creationDate": (creationDate) ? [NSString stringWithFormat:@"%.0f", [creationDate timeIntervalSince1970]] : [NSNull null],
        @"modificationDate": (modificationDate) ? [NSString stringWithFormat:@"%.0f", [modificationDate timeIntervalSince1970]] : [NSNull null],
        @"duration": (duration) ? duration : [NSNull null]
    };
}

// See https://stackoverflow.com/questions/4147311/finding-image-type-from-nsdata-or-uiimage
- (NSString *)determineMimeTypeFromImageData:(NSData *)data {
    uint8_t c;
    [data getBytes:&c length:1];
    
    switch (c) {
        case 0xFF:
            return @"image/jpeg";
        case 0x89:
            return @"image/png";
        case 0x47:
            return @"image/gif";
        case 0x49:
        case 0x4D:
            return @"image/tiff";
        case 0x00:
            return @"image/heic";
    }
    return @"";
}

- (void)qb_imagePickerController:(QBImagePickerController *)imagePickerController
          didFinishPickingAssets:(NSArray *)assets {
    
    PHImageManager *manager = [PHImageManager defaultManager];
    PHImageRequestOptions* options = [[PHImageRequestOptions alloc] init];
    options.synchronous = NO;
    options.networkAccessAllowed = YES;
    
    if ([[[self options] objectForKey:@"multiple"] boolValue]) {
        NSMutableArray *selections = [NSMutableArray arrayWithCapacity:assets.count];
        
        for (int i = 0; i < assets.count; i++) {
            [selections addObject:[NSNull null]];
        }

        [self showActivityIndicator:^(UIActivityIndicatorView *indicatorView, UIView *overlayView) {
            NSLock *lock = [[NSLock alloc] init];
            __block int processed = 0;

            for (int index = 0; index < assets.count; index++) {
                PHAsset *phAsset = assets[index];

                if (phAsset.mediaType == PHAssetMediaTypeVideo) {
                    [self getVideoAsset:phAsset completion:^(NSDictionary* video) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [lock lock];
                            
                            if (video == nil) {
                                [indicatorView stopAnimating];
                                [overlayView removeFromSuperview];
                                [imagePickerController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                                    self.reject(ERROR_CANNOT_PROCESS_VIDEO_KEY, ERROR_CANNOT_PROCESS_VIDEO_MSG, nil);
                                }]];
                                return;
                            }
                            
                            [selections replaceObjectAtIndex:index withObject:video];
                            processed++;
                            [lock unlock];
                            
                            if (processed == [assets count]) {
                                [indicatorView stopAnimating];
                                [overlayView removeFromSuperview];
                                [imagePickerController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                                    self.resolve(selections);
                                }]];
                                return;
                            }
                        });
                    }];
                } else {
                    [phAsset requestContentEditingInputWithOptions:nil completionHandler:^(PHContentEditingInput * _Nullable contentEditingInput, NSDictionary * _Nonnull info) {
                        [manager
                         requestImageDataForAsset:phAsset
                         options:options
                         resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
                            
                            NSURL *sourceURL = contentEditingInput.fullSizeImageURL;
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [lock lock];
                                @autoreleasepool {
                                    UIImage *imgT = [UIImage imageWithData:imageData];
                                    
                                    Boolean forceJpg = [[self.options valueForKey:@"forceJpg"] boolValue];
                                    
                                    NSNumber *compressQuality = [self.options valueForKey:@"compressImageQuality"];
                                    Boolean isLossless = (compressQuality == nil || [compressQuality floatValue] >= 0.8);
                                    
                                    NSNumber *maxWidth = [self.options valueForKey:@"compressImageMaxWidth"];
                                    Boolean useOriginalWidth = (maxWidth == nil || [maxWidth integerValue] >= imgT.size.width);
                                    
                                    NSNumber *maxHeight = [self.options valueForKey:@"compressImageMaxHeight"];
                                    Boolean useOriginalHeight = (maxHeight == nil || [maxHeight integerValue] >= imgT.size.height);
                                    
                                    NSString *mimeType = [self determineMimeTypeFromImageData:imageData];
                                    Boolean isKnownMimeType = [mimeType length] > 0;
                                    
                                    ImageResult *imageResult = [[ImageResult alloc] init];
                                    if (isLossless && useOriginalWidth && useOriginalHeight && isKnownMimeType && !forceJpg) {
                                        // Use original, unmodified image
                                        imageResult.data = imageData;
                                        imageResult.width = @(imgT.size.width);
                                        imageResult.height = @(imgT.size.height);
                                        imageResult.mime = mimeType;
                                        imageResult.image = imgT;
                                    } else {
                                        imageResult = [self.compression compressImage:[imgT fixOrientation] withOptions:self.options];
                                    }
                                    
                                    NSString *filePath = @"";
                                    if([[self.options objectForKey:@"writeTempFile"] boolValue]) {
                                        
                                        filePath = [self persistFile:imageResult.data];
                                        
                                        if (filePath == nil) {
                                            [indicatorView stopAnimating];
                                            [overlayView removeFromSuperview];
                                            [imagePickerController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                                                self.reject(ERROR_CANNOT_SAVE_IMAGE_KEY, ERROR_CANNOT_SAVE_IMAGE_MSG, nil);
                                            }]];
                                            return;
                                        }
                                    }
                                    
                                    NSDictionary* exif = nil;
                                    if([[self.options objectForKey:@"includeExif"] boolValue]) {
                                        exif = [[CIImage imageWithData:imageData] properties];
                                    }

                                    [selections replaceObjectAtIndex:index withObject:[self createAttachmentResponse:filePath
                                                                                                            withExif: exif
                                                                                                       withSourceURL:[sourceURL absoluteString]
                                                                                                 withLocalIdentifier: phAsset.localIdentifier
                                                                                                        withFilename: [phAsset valueForKey:@"filename"]
                                                                                                           withWidth:imageResult.width
                                                                                                          withHeight:imageResult.height
                                                                                                            withMime:imageResult.mime
                                                                                                            withSize:[NSNumber numberWithUnsignedInteger:imageResult.data.length]
                                                                                                        withDuration: nil
                                                                                                            withData:[[self.options objectForKey:@"includeBase64"] boolValue] ? [imageResult.data base64EncodedStringWithOptions:0]: nil
                                                                                                            withRect:CGRectNull
                                                                                                    withCreationDate:phAsset.creationDate
                                                                                                withModificationDate:phAsset.modificationDate
                                                                                      ]];
                                }
                                processed++;
                                [lock unlock];
                                
                                if (processed == [assets count]) {
                                    
                                    [indicatorView stopAnimating];
                                    [overlayView removeFromSuperview];
                                    [imagePickerController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                                        self.resolve(selections);
                                    }]];
                                    return;
                                }
                            });
                        }];
                    }];
                }
            }
        }];
    } else {
        PHAsset *phAsset = [assets objectAtIndex:0];
        
        [self showActivityIndicator:^(UIActivityIndicatorView *indicatorView, UIView *overlayView) {
            if (phAsset.mediaType == PHAssetMediaTypeVideo) {
                [self getVideoAsset:phAsset completion:^(NSDictionary* video) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [indicatorView stopAnimating];
                        [overlayView removeFromSuperview];
                        [imagePickerController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                            if (video != nil) {
                                self.resolve(video);
                            } else {
                                self.reject(ERROR_CANNOT_PROCESS_VIDEO_KEY, ERROR_CANNOT_PROCESS_VIDEO_MSG, nil);
                            }
                        }]];
                    });
                }];
            } else {
                [phAsset requestContentEditingInputWithOptions:nil completionHandler:^(PHContentEditingInput * _Nullable contentEditingInput, NSDictionary * _Nonnull info) {
                    [manager
                     requestImageDataForAsset:phAsset
                     options:options
                     resultHandler:^(NSData *imageData, NSString *dataUTI,
                                     UIImageOrientation orientation,
                                     NSDictionary *info) {
                        NSURL *sourceURL = contentEditingInput.fullSizeImageURL;
                        NSDictionary* exif;
                        if([[self.options objectForKey:@"includeExif"] boolValue]) {
                            exif = [[CIImage imageWithData:imageData] properties];
                        }
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [indicatorView stopAnimating];
                            [overlayView removeFromSuperview];
                            
                            [self processSingleImagePick:[UIImage imageWithData:imageData]
                                                withExif: exif
                                      withViewController:imagePickerController
                                           withSourceURL:[sourceURL absoluteString]
                                     withLocalIdentifier:phAsset.localIdentifier
                                            withFilename:[phAsset valueForKey:@"filename"]
                                        withCreationDate:phAsset.creationDate
                                    withModificationDate:phAsset.modificationDate];
                        });
                    }];
                }];
            }
        }];
    }
}

- (void)qb_imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController {
    [imagePickerController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
        self.reject(ERROR_PICKER_CANCEL_KEY, ERROR_PICKER_CANCEL_MSG, nil);
    }]];
}

// when user selected single image, with camera or from photo gallery,
// this method will take care of attaching image metadata, and sending image to cropping controller
// or to user directly
- (void) processSingleImagePick:(UIImage*)image withExif:(NSDictionary*) exif withViewController:(UIViewController*)viewController withSourceURL:(NSString*)sourceURL withLocalIdentifier:(NSString*)localIdentifier withFilename:(NSString*)filename withCreationDate:(NSDate*)creationDate withModificationDate:(NSDate*)modificationDate {
    
    if (image == nil) {
        [viewController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
            self.reject(ERROR_PICKER_NO_DATA_KEY, ERROR_PICKER_NO_DATA_MSG, nil);
        }]];
        return;
    }
    
    NSLog(@"id: %@ filename: %@", localIdentifier, filename);
    
    if ([[[self options] objectForKey:@"cropping"] boolValue]) {
        self.croppingFile = [[NSMutableDictionary alloc] init];
        self.croppingFile[@"sourceURL"] = sourceURL;
        self.croppingFile[@"localIdentifier"] = localIdentifier;
        self.croppingFile[@"filename"] = filename;
        self.croppingFile[@"creationDate"] = creationDate;
        self.croppingFile[@"modifcationDate"] = modificationDate;
        NSLog(@"CroppingFile %@", self.croppingFile);
        
        [self cropImage:[image fixOrientation]];
    } else {
        ImageResult *imageResult = [self.compression compressImage:[image fixOrientation]  withOptions:self.options];
        NSString *filePath = [self persistFile:imageResult.data];
        if (filePath == nil) {
            [viewController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                self.reject(ERROR_CANNOT_SAVE_IMAGE_KEY, ERROR_CANNOT_SAVE_IMAGE_MSG, nil);
            }]];
            return;
        }
        
        // Wait for viewController to dismiss before resolving, or we lose the ability to display
        // Alert.alert in the .then() handler.
        [viewController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
            self.resolve([self createAttachmentResponse:filePath
                                               withExif:exif
                                          withSourceURL:sourceURL
                                    withLocalIdentifier:localIdentifier
                                           withFilename:filename
                                              withWidth:imageResult.width
                                             withHeight:imageResult.height
                                               withMime:imageResult.mime
                                               withSize:[NSNumber numberWithUnsignedInteger:imageResult.data.length]
                                           withDuration: nil
                                               withData:[[self.options objectForKey:@"includeBase64"] boolValue] ? [imageResult.data base64EncodedStringWithOptions:0] : nil
                                               withRect:CGRectNull
                                       withCreationDate:creationDate
                                   withModificationDate:modificationDate
                          ]);
        }]];
    }
}

- (void)dismissCropper:(UIViewController *)controller selectionDone:(BOOL)selectionDone completion:(void (^)(void))completion {
    switch (self.currentSelectionMode) {
        case CROPPING:
            [controller dismissViewControllerAnimated:YES completion:completion];
            break;
        case PICKER:
            if (selectionDone) {
                [controller.presentingViewController.presentingViewController dismissViewControllerAnimated:YES completion:completion];
            } else {
                // if user opened picker, tried to crop image, and cancelled cropping
                // return him to the image selection instead of returning him to the app
                [controller.presentingViewController dismissViewControllerAnimated:YES completion:completion];
            }
            break;
        case CAMERA:
            [controller.presentingViewController.presentingViewController dismissViewControllerAnimated:YES completion:completion];
            break;
    }
}

// The original image has been cropped.
- (void)imageCropViewController:(UIViewController *)controller
                   didCropImage:(UIImage *)croppedImage
                  usingCropRect:(CGRect)cropRect {
    
    // we have correct rect, but not correct dimensions
    // so resize image
    CGSize desiredImageSize = CGSizeMake([[[self options] objectForKey:@"width"] intValue],
                                         [[[self options] objectForKey:@"height"] intValue]);
    
    UIImage *resizedImage = [croppedImage resizedImageToFitInSize:desiredImageSize scaleIfSmaller:YES];
    ImageResult *imageResult = [self.compression compressImage:resizedImage withOptions:self.options];
    
    NSString *filePath = [self persistFile:imageResult.data];
    if (filePath == nil) {
        [self dismissCropper:controller selectionDone:YES completion:[self waitAnimationEnd:^{
            self.reject(ERROR_CANNOT_SAVE_IMAGE_KEY, ERROR_CANNOT_SAVE_IMAGE_MSG, nil);
        }]];
        return;
    }
    
    NSDictionary* exif = nil;
    if([[self.options objectForKey:@"includeExif"] boolValue]) {
        exif = [[CIImage imageWithData:imageResult.data] properties];
    }
    
    [self dismissCropper:controller selectionDone:YES completion:[self waitAnimationEnd:^{
        self.resolve([self createAttachmentResponse:filePath
                                           withExif: exif
                                      withSourceURL: self.croppingFile[@"sourceURL"]
                                withLocalIdentifier: self.croppingFile[@"localIdentifier"]
                                       withFilename: self.croppingFile[@"filename"]
                                          withWidth:imageResult.width
                                         withHeight:imageResult.height
                                           withMime:imageResult.mime
                                           withSize:[NSNumber numberWithUnsignedInteger:imageResult.data.length]
                                       withDuration: nil
                                           withData:[[self.options objectForKey:@"includeBase64"] boolValue] ? [imageResult.data base64EncodedStringWithOptions:0] : nil
                                           withRect:cropRect
                                   withCreationDate:self.croppingFile[@"creationDate"]
                               withModificationDate:self.croppingFile[@"modificationDate"]
                      ]);
    }]];
}

// at the moment it is not possible to upload image by reading PHAsset
// we are saving image and saving it to the tmp location where we are allowed to access image later
- (NSString*) persistFile:(NSData*)data {
    // create temp file
    NSString *tmpDirFullPath = [self getTmpDirectory];
    NSString *filePath = [tmpDirFullPath stringByAppendingString:[[NSUUID UUID] UUIDString]];
    filePath = [filePath stringByAppendingString:@".jpg"];
    
    // save cropped file
    BOOL status = [data writeToFile:filePath atomically:YES];
    if (!status) {
        return nil;
    }
    
    return filePath;
}

+ (NSDictionary *)cgRectToDictionary:(CGRect)rect {
    return @{
        @"x": [NSNumber numberWithFloat: rect.origin.x],
        @"y": [NSNumber numberWithFloat: rect.origin.y],
        @"width": [NSNumber numberWithFloat: CGRectGetWidth(rect)],
        @"height": [NSNumber numberWithFloat: CGRectGetHeight(rect)]
    };
}

// Assumes input like "#00FF00" (#RRGGBB).
+ (UIColor *)colorFromHexString:(NSString *)hexString {
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner setScanLocation:1]; // bypass '#' character
    [scanner scanHexInt:&rgbValue];
    return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:1.0];
}

#pragma mark - TOCCropViewController Implementation
- (void)cropImage:(UIImage *)image {
    dispatch_async(dispatch_get_main_queue(), ^{
        TOCropViewController *cropVC;
        if ([[[self options] objectForKey:@"cropperCircleOverlay"] boolValue]) {
            cropVC = [[TOCropViewController alloc] initWithCroppingStyle:TOCropViewCroppingStyleCircular image:image];
        } else {
            cropVC = [[TOCropViewController alloc] initWithImage:image];
            CGFloat widthRatio = [[self.options objectForKey:@"width"] floatValue];
            CGFloat heightRatio = [[self.options objectForKey:@"height"] floatValue];
            if (widthRatio > 0 && heightRatio > 0){
                CGSize aspectRatio = CGSizeMake(widthRatio, heightRatio);
                cropVC.customAspectRatio = aspectRatio;
                
            }
            cropVC.aspectRatioLockEnabled = ![[self.options objectForKey:@"freeStyleCropEnabled"] boolValue];
            cropVC.resetAspectRatioEnabled = !cropVC.aspectRatioLockEnabled;
        }
        
        cropVC.title = [[self options] objectForKey:@"cropperToolbarTitle"];
        cropVC.delegate = self;

        NSString* rawDoneButtonColor = [self.options objectForKey:@"cropperChooseColor"];
        NSString* rawCancelButtonColor = [self.options objectForKey:@"cropperCancelColor"];

        if (rawDoneButtonColor) {
            cropVC.doneButtonColor = [ImageCropPicker colorFromHexString: rawDoneButtonColor];
        }
        if (rawCancelButtonColor) {
            cropVC.cancelButtonColor = [ImageCropPicker colorFromHexString: rawCancelButtonColor];
        }
        
        cropVC.doneButtonTitle = [self.options objectForKey:@"cropperChooseText"];
        cropVC.cancelButtonTitle = [self.options objectForKey:@"cropperCancelText"];
        cropVC.rotateButtonsHidden = [[self.options objectForKey:@"cropperRotateButtonsHidden"] boolValue];
        
        cropVC.modalPresentationStyle = UIModalPresentationFullScreen;
        if (@available(iOS 15.0, *)) {
            cropVC.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        }
        
        [[self getRootVC] presentViewController:cropVC animated:FALSE completion:nil];
    });
}
#pragma mark - TOCropViewController Delegate
- (void)cropViewController:(TOCropViewController *)cropViewController didCropToImage:(UIImage *)image withRect:(CGRect)cropRect angle:(NSInteger)angle {
    [self imageCropViewController:cropViewController didCropImage:image usingCropRect:cropRect];
}

- (void)cropViewController:(TOCropViewController *)cropViewController didFinishCancelled:(BOOL)cancelled {
    [self dismissCropper:cropViewController selectionDone:NO completion:[self waitAnimationEnd:^{
        if (self.currentSelectionMode == CROPPING) {
            self.reject(ERROR_PICKER_CANCEL_KEY, ERROR_PICKER_CANCEL_MSG, nil);
        }
    }]];
}

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
(const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeImageCropPickerSpecJSI>(params);
}
#endif

@end
