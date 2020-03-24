//
//  AVCaptureEngine.m
//  AVCaptureDemo
//
//  Created by Sand Pei on 12-4-13.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "AVCaptureEngine.h"

#import <IOKit/audio/IOAudioTypes.h>

#define MAX_PLANE_COUNT         3

#define OPEN_SCREEN_CAPTURE     0
#define OPEN_CAPTURE_THREAD     1
#define SET_CONNECTION_FPS      0
#define USE_CAPTURE_LAYER       0
#define ENABLE_REMOVE_LAYER     1

NSString* kDefaultFormat = @"kCVPixelFormatType_Default";
NSString* kScalingMode = AVVideoScalingModeResizeAspectFill;
float kFrameRate = 30.0;

static int callseq = 0;

#if OPEN_CAPTURE_THREAD
static void capture_cleanup(void* p)
{
    NSLog(@"capture queue cleanup, retainCount = %d, callseq = %d", (int)[(id)p retainCount], callseq++);
    [(id)p release];
}
#endif

@interface AVCaptureEngine ()

// Methods for internal use
- (void)addObserversForDevices;
- (void)removeObserversForDevices;

- (void)updateCaptureDevices;
- (void)updateFrameRate;

- (void)getCaptureDeviceInfo;
- (void)setCaptureOutputInfo;

- (NSNumber*)getFormatNumber:(NSString*)formatString;
- (NSString*)getFormatString:(NSNumber*)formatNumber;

- (NSSize)getResolutionSize:(NSString*)sessionPreset;

- (NSString*)getCaptureLayerStatusString:(AVQueuedSampleBufferRenderingStatus)status;
- (BOOL)isCaptureLayerHidden;
- (void)setCaptureLayerHidden:(BOOL)hidden;

@end

@implementation AVCaptureEngine

- (id)initWithView:(NSView*)pView CaptureView:(MyAVCaptureView*)cView
{
    self = [super init];
	if(NULL != self)
	{
        NSError *error = nil;
        
        // create capture session
        captureSession = [[AVCaptureSession alloc] init];
        
        // add capture notification observers
		NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
		id runtimeErrorObserver = [notificationCenter addObserverForName:AVCaptureSessionRuntimeErrorNotification
																  object:captureSession
																   queue:[NSOperationQueue mainQueue]
															  usingBlock:^(NSNotification *note) {
																  dispatch_async(dispatch_get_main_queue(), ^(void) {
																	  NSLog(@"capture session runtime error: %@",[[note userInfo] objectForKey:AVCaptureSessionErrorKey]);
																  });
															  }];
		id didStartRunningObserver = [notificationCenter addObserverForName:AVCaptureSessionDidStartRunningNotification
																	 object:captureSession
																	  queue:[NSOperationQueue mainQueue]
																 usingBlock:^(NSNotification *note) {
																	 NSLog(@"did start running, callseq = %d", callseq++);
                                                                     frameCount = 0;
                                                                     totalFrameCount = 0;
                                                                     fpsTimer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)1.0 target:self selector:@selector(updateFrameRate) userInfo:NULL repeats:YES];
																 }];
		id didStopRunningObserver = [notificationCenter addObserverForName:AVCaptureSessionDidStopRunningNotification
																	object:captureSession
																	 queue:[NSOperationQueue mainQueue]
																usingBlock:^(NSNotification *note) {
																	NSLog(@"did stop running, callseq = %d", callseq++);
                                                                    [fpsTimer invalidate];
                                                                    fpsTimer = nil;
																}];
		id deviceWasConnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasConnectedNotification
																		object:nil
																		 queue:[NSOperationQueue mainQueue]
																	usingBlock:^(NSNotification *note) {
                                                                        AVCaptureDevice *device = [note object];
                                                                        NSLog(@"device was connected, uniqueID = %@, localizedName = %@, mediaType = V:%d A:%d M:%d", [device uniqueID],[device localizedName], [device hasMediaType: AVMediaTypeVideo], [device hasMediaType: AVMediaTypeAudio], [device hasMediaType: AVMediaTypeMuxed]);
                                                                        if(YES == [device hasMediaType:AVMediaTypeVideo]) {
                                                                            [self updateCaptureDevices];
                                                                        }
																	}];
		id deviceWasDisconnectedObserver = [notificationCenter addObserverForName:AVCaptureDeviceWasDisconnectedNotification
																		   object:nil
																			queue:[NSOperationQueue mainQueue]
																	   usingBlock:^(NSNotification *note) {
                                                                           AVCaptureDevice *device = [note object];
																		   NSLog(@"device was disconnected, uniqueID = %@, localizedName = %@, mediaType = V:%d A:%d M:%d", [device uniqueID],[device localizedName], [device hasMediaType: AVMediaTypeVideo], [device hasMediaType: AVMediaTypeAudio], [device hasMediaType: AVMediaTypeMuxed]);
                                                                           if(YES == [device hasMediaType:AVMediaTypeVideo]) {
                                                                               [self updateCaptureDevices];
                                                                           }
																	   }];
		observers = [[NSArray alloc] initWithObjects:runtimeErrorObserver, didStartRunningObserver, didStopRunningObserver, deviceWasConnectedObserver, deviceWasDisconnectedObserver, nil];
        
        // select capture device
        captureDeviceIndex = -1;
		captureDevice = nil;
		devicesArray = [[[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] arrayByAddingObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeMuxed]] retain];
        [self addObserversForDevices];
		if([devicesArray count] > 0)
		{
			captureDeviceIndex = 0;
			captureDevice = [devicesArray objectAtIndex:captureDeviceIndex];
		}
        
        // get capture device info
        [self getCaptureDeviceInfo];
        
        [captureSession beginConfiguration];
        
        // create capture input
        captureInput = [[AVCaptureDeviceInput alloc] initWithDevice:captureDevice error:&error];
#if !OPEN_SCREEN_CAPTURE
        [captureSession addInput:captureInput];
#endif
        
        // create screen capture input
        screenInput = [[AVCaptureScreenInput alloc] initWithDisplayID:kCGDirectMainDisplay];
        bScreenCapture = NO;
#if OPEN_SCREEN_CAPTURE
        [captureSession addInput:screenInput];
#endif
        
        // create capture output
        captureOutput = [[AVCaptureVideoDataOutput alloc] init];
        [captureSession addOutput:captureOutput];
        
        // get active info
        activeResolution = [captureSession sessionPreset];
        NSDictionary* videoSettings = [captureOutput videoSettings];
        activePixelFormatType = [videoSettings objectForKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
        activeScalingMode = [videoSettings objectForKey:AVVideoScalingModeKey];
        NSLog(@"[init] Get default videoSettings: %@", videoSettings);
  
        [captureSession setSessionPreset:activeResolution];
        
        // set capture output
        [self setCaptureOutputInfo];
        
        // attach preview to session
        previewView = pView;
        CALayer *previewViewLayer = [previewView layer];
//        [previewViewLayer setBackgroundColor:CGColorGetConstantColor(kCGColorBlack)];
        CGColorRef grayColor = CGColorCreateGenericGray(0.5, 1.0);
        [previewViewLayer setBackgroundColor:grayColor];
        CFRelease(grayColor);
        
        previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
        [previewLayer setFrame:[previewViewLayer bounds]];
        [previewLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
        [previewViewLayer addSublayer:previewLayer];
        
        // set preview layer
    //  [captureLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
        AVCaptureConnection *previewConnection = [previewLayer connection];
        if(YES == [previewConnection isVideoMirroringSupported])
        {
            // [previewConnection setAutomaticallyAdjustsVideoMirroring:YES];
            // [previewConnection setVideoMirrored:YES];
 
#if SET_CONNECTION_FPS
            if(YES == [previewConnection respondsToSelector:@selector(isVideoMinFrameDurationSupported)])
            {
                BOOL supportsVideoMinFrameDuration = [previewConnection isVideoMinFrameDurationSupported];
                if(YES == supportsVideoMinFrameDuration)
                {
                    [previewConnection setVideoMinFrameDuration: CMTimeMakeWithSeconds(1.0 / kFrameRate, 10000)];
                }
            }
            if(YES == [previewConnection respondsToSelector:@selector(isVideoMaxFrameDurationSupported)])
            {
                BOOL supportsVideoMaxFrameDuration = [previewConnection isVideoMaxFrameDurationSupported];
                if(YES == supportsVideoMaxFrameDuration)
                {
                    [previewConnection setVideoMaxFrameDuration: CMTimeMakeWithSeconds(1.0 / kFrameRate, 10000)];
                }
            }
#endif
        }
        // end set
        
        [captureSession commitConfiguration];
        
        realPixelFormat = [activePixelFormatType unsignedIntValue];
        realPixelWidth = 0;
        realPixelHeight = 0;
        realFrameRate = 0;
        
        frameCount = 0;
        totalFrameCount = 0;
        
        captureView = cView;
        CALayer *captureViewLayer = [captureView layer];
        CGColorRef blackColor = CGColorCreateGenericGray(0.0, 1.0);
        [captureViewLayer setBackgroundColor:blackColor];
        CFRelease(blackColor);
        // create and attach capture layer
        captureLayer = [[AVSampleBufferDisplayLayer alloc] init];
        captureLayer.opaque = TRUE;
        captureLayer.frame = captureView.bounds;
        [captureLayer setAutoresizingMask:kCALayerWidthSizable | kCALayerHeightSizable];
        [captureLayer setAffineTransform:CGAffineTransformRotate(captureLayer.affineTransform, (0.0f * M_PI) / 180.0f)];
        captureLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [captureViewLayer addSublayer:captureLayer];
        
        captuerDelegate = nil;
    }
    
    return self;
}

- (void)dealloc
{
    [fpsTimer invalidate];
    fpsTimer = nil;
    
    [captureLayer removeFromSuperlayer];
    [captureLayer release];
    
    [captureSession beginConfiguration];
    [previewLayer removeFromSuperlayer];
    [previewLayer release];
    [captureSession removeInput:captureInput];
    [captureSession removeInput:screenInput];
    [captureSession removeOutput:captureOutput];
    [captureInput release];
    [screenInput release];
    [captureOutput release];
    [captureSession commitConfiguration];
    
    [captureSession release];
    
    [self removeObserversForDevices];
    [devicesArray release];
    
    // remove observers
	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
	for (id observer in observers)
		[notificationCenter removeObserver:observer];
	[observers release];
    
    [super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context
{
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(connected))]) {
        NSLog(@"%@ connected value changed: %@", object, change);
    }
    else if ([keyPath isEqualToString:NSStringFromSelector(@selector(suspended))]) {
        NSLog(@"%@ suspended value changed: %@", object, change);
    }
    else if ([keyPath isEqualToString:NSStringFromSelector(@selector(inUseByAnotherApplication))]) {
        NSLog(@"%@ inUseByAnotherApplication value changed: %@", object, change);
    }
    else if ([keyPath isEqualToString:NSStringFromSelector(@selector(activeFormat))]) {
        NSLog(@"%@ activeFormat value changed: %@", object, change);
        [captuerDelegate deviceChangeWithType:AVCaptureDeviceChangeActiveFormat];
    }
    else if ([keyPath isEqualToString:NSStringFromSelector(@selector(activeVideoMinFrameDuration))]) {
        NSLog(@"%@ activeVideoMinFrameDuration value changed: %@", object, change);
        [captuerDelegate deviceChangeWithType:AVCaptureDeviceChangeActiveFrameRate];
    }
    else if ([keyPath isEqualToString:NSStringFromSelector(@selector(activeVideoMaxFrameDuration))]) {
        NSLog(@"%@ activeVideoMaxFrameDuration value changed: %@", object, change);
    }
}

- (void)setDelegate:(id<AVCaptureEngineDelegate>)delegate
{
    captuerDelegate = delegate;
}

- (BOOL)isRunning
{
    return [captureSession isRunning];
}

- (void)startRunning
{
    NSLog(@"startRunning begin, isRunning = %d, retainCount = %d, callseq = %d", [captureSession isRunning], (int)[self retainCount], callseq++);
  
#if OPEN_CAPTURE_THREAD
    dispatch_queue_t wseAVCaptureQueue = dispatch_queue_create("WseAVCaptureQueue", nil);
    [captureOutput setSampleBufferDelegate:self queue:wseAVCaptureQueue];
    dispatch_set_context(wseAVCaptureQueue, [self retain]);
    dispatch_set_finalizer_f(wseAVCaptureQueue, capture_cleanup);
    dispatch_release(wseAVCaptureQueue);
#else
    [captureOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
#endif
    
    [captureSession startRunning];
    NSLog(@"startRunning end, isRunning = %d, retainCount = %d, callseq = %d", [captureSession isRunning], (int)[self retainCount], callseq++);
}

- (void)stopRunning
{
    NSLog(@"stopRunning begin, isRunning = %d, retainCount = %d, callseq = %d", [captureSession isRunning], (int)[self retainCount], callseq++);
    
    [captureSession stopRunning];
    
    [captureOutput setSampleBufferDelegate:NULL queue:NULL];
    
    NSLog(@"stopRunning end, isRunning = %d, retainCount = %d, callseq = %d", [captureSession isRunning], (int)[self retainCount], callseq++);
}

- (void)switchDevice
{
    NSError *error = nil;
	BOOL bRun = [captureSession isRunning];
	
	if([devicesArray count] > 1 || ([devicesArray count] == 1 && captureDeviceIndex == -1))
	{
		captureDeviceIndex++;
		captureDevice = [devicesArray objectAtIndex:(captureDeviceIndex % [devicesArray count])];
        
        AVCaptureDeviceInput *releaseCaptureInput = captureInput;
        captureInput = [[AVCaptureDeviceInput alloc] initWithDevice:captureDevice error:&error];
        
        if(nil != captureInput)
        {
            if(NO == bScreenCapture)
            {
                if(YES == bRun)
                {
                    [self stopRunning];
                }
                
                [captureSession beginConfiguration];
                
                if(NO == [captureDevice supportsAVCaptureSessionPreset:activeResolution])
                {
                    [captureSession setSessionPreset:AVCaptureSessionPresetHigh];
                }
                
                [captureSession removeInput:releaseCaptureInput];
            #if !OPEN_SCREEN_CAPTURE
                [captureSession addInput:captureInput];
            #endif
                
                [self getCaptureDeviceInfo];
                [self setCaptureOutputInfo];
                
                [captureSession commitConfiguration];
                
                if(YES == bRun)
                {
                    [self startRunning];
                }
            }
            
            [releaseCaptureInput release];
        }
        else
        {
            NSLog(@"[switchDevice] Switch device [%@] fail, error: %@", [captureDevice localizedName], error);
        }
	}
}

- (void)swtichScreenCapture
{
    [captureSession beginConfiguration];
    if(YES == bScreenCapture)
    {
        [captureSession removeInput:screenInput];
        [captureSession addInput:captureInput];
        bScreenCapture = NO;
    }
    else
    {
        [captureSession removeInput:captureInput];
        [captureSession addInput:screenInput];
        bScreenCapture = YES;
    }
    [captureSession commitConfiguration];
}

- (void)printDeviceInfo
{
    [self getCaptureDeviceInfo];
}

- (NSString*)currentDeviceName
{
    // device display name
	return [captureDevice localizedName];
}

- (NSArray*)allFormats
{
    NSArray *availableVideoCVPixelFormatTypes = [captureOutput availableVideoCVPixelFormatTypes];
    NSMutableArray* formatArray = [NSMutableArray arrayWithCapacity:[availableVideoCVPixelFormatTypes count]];
    for(NSNumber *pixelFormatType in availableVideoCVPixelFormatTypes)
    {
        [formatArray addObject:[self getFormatString:pixelFormatType]];
    }
    [formatArray addObject:kDefaultFormat];
    
    return formatArray;
}

- (NSArray*)allCodecTypes
{
    // check codec type result
    /*
     kCMVideoCodecType_H264             = 'avc1',
     kCMVideoCodecType_JPEG             = 'jpeg',
    */
    
    NSArray *availableVideoCodecTypes = [captureOutput availableVideoCodecTypes];
    NSMutableArray* typeArray = [NSMutableArray arrayWithCapacity:[availableVideoCodecTypes count]];
    for(NSString *codecType in availableVideoCodecTypes)
    {
        [typeArray addObject:codecType];
    }
    
    return typeArray;
}

- (NSArray*)allResolutions
{
    NSMutableArray* resolutionArray = [NSMutableArray arrayWithCapacity:9];
    if(YES == [captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPresetPhoto])
    {
        [resolutionArray addObject:AVCaptureSessionPresetPhoto];
    }
    if(YES == [captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPresetHigh])
    {
        [resolutionArray addObject:AVCaptureSessionPresetHigh];
    }
    if(YES == [captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPresetMedium])
    {
        [resolutionArray addObject:AVCaptureSessionPresetMedium];
    }
    if(YES == [captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPresetLow])
    {
        [resolutionArray addObject:AVCaptureSessionPresetLow];
    }
    if(YES == [captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPreset320x240])
    {
        [resolutionArray addObject:AVCaptureSessionPreset320x240];
    }
    if(YES == [captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPreset352x288])
    {
        [resolutionArray addObject:AVCaptureSessionPreset352x288];
    }
    if(YES == [captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPreset640x480])
    {
        [resolutionArray addObject:AVCaptureSessionPreset640x480];
    }
    if(YES == [captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPreset960x540])
    {
        [resolutionArray addObject:AVCaptureSessionPreset960x540];
    }
    if(YES == [captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPreset1280x720])
    {
        [resolutionArray addObject:AVCaptureSessionPreset1280x720];
    }
    if(YES == [captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPresetiFrame960x540])
    {
        [resolutionArray addObject:AVCaptureSessionPresetiFrame960x540];
    }
    if(YES == [captureDevice supportsAVCaptureSessionPreset:AVCaptureSessionPresetiFrame1280x720])
    {
        [resolutionArray addObject:AVCaptureSessionPresetiFrame1280x720];
    }
    
    return resolutionArray;
}

- (NSArray*)allScalingModes
{
    NSMutableArray* scalingModeArray = [NSMutableArray arrayWithCapacity:4];
    [scalingModeArray addObject:AVVideoScalingModeFit];
    [scalingModeArray addObject:AVVideoScalingModeResize];
    [scalingModeArray addObject:AVVideoScalingModeResizeAspect];
    [scalingModeArray addObject:AVVideoScalingModeResizeAspectFill];
    
    return scalingModeArray;
}

- (NSArray*)allFrameRates
{
    NSArray *videoSupportedFrameRateRanges = [[captureDevice activeFormat] videoSupportedFrameRateRanges];
    NSMutableArray* frameRateArray = [NSMutableArray arrayWithCapacity:[videoSupportedFrameRateRanges count]];
    AVFrameRateRange * frameRateRange = nil;
    for(frameRateRange in videoSupportedFrameRateRanges)
    {
        [frameRateArray addObject:[NSString stringWithFormat:@"%.2f" ,[frameRateRange maxFrameRate]]];
    }
    
    return frameRateArray;
}

- (NSArray*)allDeviceFormats
{
    NSArray *formats = [captureDevice formats];
    NSMutableArray* formatArray = [NSMutableArray arrayWithCapacity:[formats count]];
    CMFormatDescriptionRef formatDescription = nil;
    FourCharCode codecType = 0;
    CMVideoDimensions dimensions = {0, 0};
    for(AVCaptureDeviceFormat *format in formats)
    {
        formatDescription = [format formatDescription];
        codecType = CMVideoFormatDescriptionGetCodecType(formatDescription);
        dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
        [formatArray addObject:[NSString stringWithFormat:@"%@, %dx%d", NSFileTypeForHFSTypeCode(codecType), dimensions.width, dimensions.height]];
    }
    
    return formatArray;
}

- (void)setFormat:(NSString*)format
{
    NSNumber *pixelFormatType = nil;
    BOOL bDefaultFormat = NO;
    if(NSOrderedSame == [format compare:kDefaultFormat])
    {
        bDefaultFormat = YES;
    }
    else
    {
        pixelFormatType = [self getFormatNumber:format];
        if(nil == pixelFormatType)
        {
            return;
        }
    }
    
    activePixelFormatType = pixelFormatType;
    
    NSDictionary* videoSettings = [captureOutput videoSettings];
    NSLog(@"[setFormat] Get videoSettings before set: %@", videoSettings);
    
    NSMutableDictionary* newVideoSettings = [NSMutableDictionary dictionaryWithCapacity:0];
    if(NO == bDefaultFormat)
    {
        [newVideoSettings addEntriesFromDictionary:videoSettings];
        [newVideoSettings setObject:activePixelFormatType forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
    }
    [captureSession beginConfiguration];
    [captureOutput setVideoSettings:newVideoSettings];
    [captureSession commitConfiguration];
    
    videoSettings = [captureOutput videoSettings];
    NSLog(@"[setFormat] Get videoSettings after set: %@", videoSettings);
}

- (void)setResolution:(NSString*)resolution
{
    activeResolution = resolution;
    
    [captureSession beginConfiguration];
    [captureSession setSessionPreset:activeResolution];
    [captureOutput setVideoSettings:nil];
    [captureSession commitConfiguration];
    
    NSDictionary* videoSettings = [captureOutput videoSettings];
    NSLog(@"[setResolution] Get videoSettings before set: %@", videoSettings);
    
    NSMutableDictionary* newVideoSettings = [NSMutableDictionary dictionaryWithCapacity:0];
    if(nil != activePixelFormatType)
    {
        [newVideoSettings addEntriesFromDictionary:videoSettings];
        [newVideoSettings setObject:activePixelFormatType forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
        [newVideoSettings setObject:kScalingMode forKey:AVVideoScalingModeKey];
    }
    [captureSession beginConfiguration];
    [captureOutput setVideoSettings:newVideoSettings];
    [captureSession commitConfiguration];
    
    videoSettings = [captureOutput videoSettings];
    NSLog(@"[setResolution] Get videoSettings after set: %@", videoSettings);
}

- (void)setScalingMode:(NSString*)scalingMode
{
    activeScalingMode = scalingMode;
    
    NSDictionary* videoSettings = [captureOutput videoSettings];
    NSLog(@"[setScalingMode] Get videoSettings before set: %@", videoSettings);
    
    NSMutableDictionary* newVideoSettings = [NSMutableDictionary dictionaryWithCapacity:0];
    if(nil != activePixelFormatType)
    {
        [newVideoSettings addEntriesFromDictionary:videoSettings];
        [newVideoSettings setObject:activeScalingMode forKey:AVVideoScalingModeKey];
    }
    [captureSession beginConfiguration];
    [captureOutput setVideoSettings:newVideoSettings];
    [captureSession commitConfiguration];
    
    videoSettings = [captureOutput videoSettings];
    NSLog(@"[setScalingMode] Get videoSettings after set: %@", videoSettings);
}

- (void)setFrameRate:(NSString*)frameRate Index:(NSInteger)index
{
    float maxFrameRate = [frameRate floatValue];
    NSLog(@"[setFrameRate] set new frame rate: %.2f, index = %d", maxFrameRate, (int)index);
    
#if SET_CONNECTION_FPS
    NSArray *connections = [captureOutput connections];
    NSUInteger connectionCount = [connections count];
    if(connectionCount > 0)
    {
        AVCaptureConnection *connection = [connections objectAtIndex:0];
        
        [captureSession beginConfiguration];
        // set frame rate, default is 30 fps
        if(YES == [connection respondsToSelector:@selector(isVideoMinFrameDurationSupported)])
        {
            BOOL supportsVideoMinFrameDuration = [connection isVideoMinFrameDurationSupported];
            if(YES == supportsVideoMinFrameDuration)
            {
                [connection setVideoMinFrameDuration: kCMTimeInvalid];//CMTimeMakeWithSeconds(1.0 / maxFrameRate, 10000)];
            }
        }
        if(YES == [connection respondsToSelector:@selector(isVideoMaxFrameDurationSupported)])
        {
            BOOL supportsVideoMaxFrameDuration = [connection isVideoMaxFrameDurationSupported];
            if(YES == supportsVideoMaxFrameDuration)
            {
                [connection setVideoMaxFrameDuration: kCMTimeInvalid];//CMTimeMakeWithSeconds(1.0 / maxFrameRate, 10000)];
            }
        }
        [captureSession commitConfiguration];
    }
#endif
    
    NSArray *videoSupportedFrameRateRanges = [[captureDevice activeFormat] videoSupportedFrameRateRanges];
    AVFrameRateRange * frameRateRange = [videoSupportedFrameRateRanges objectAtIndex:index];
    NSError *error = nil;
    if(nil != frameRateRange && YES == [captureDevice lockForConfiguration:&error])
    {
        [captureDevice setActiveVideoMinFrameDuration:[frameRateRange minFrameDuration]];
        [captureDevice setActiveVideoMaxFrameDuration:[frameRateRange minFrameDuration]]; // If set max frame duration with range min frame duration, the API maybe throw a exception NSInvalidArgumentException.
        [captureDevice unlockForConfiguration];
        NSLog(@"[setFrameRate] set new frame rate: %@", frameRateRange);
    }
    else
    {
        NSLog(@"[setFrameRate] set new frame rate fail: %@, error: %@", frameRateRange, error);
    }
}

- (void)setDeviceFormat:(NSString*)deviceFormat Index:(NSInteger)index
{
    NSLog(@"[setDeviceFormat] set new device format: %@, index = %d", deviceFormat, (int)index);
    NSArray *formats = [captureDevice formats];
    AVCaptureDeviceFormat *format = [formats objectAtIndex:index];
    NSError *error = nil;
    if(nil != format && YES == [captureDevice lockForConfiguration:&error])
    {
        [captureDevice setActiveFormat:format];
        [captureDevice unlockForConfiguration];
        NSLog(@"[setDeviceFormat] set new device format: %@", format);
    }
    else
    {
        NSLog(@"[setDeviceFormat] set new device format fail: %@, error: %@", format, error);
    }
}

- (NSString*)activeFormat
{
    NSDictionary* videoSettings = [captureOutput videoSettings];
    NSNumber* pixelFormatType = [videoSettings objectForKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
    NSString* format = kDefaultFormat;
    if(nil != pixelFormatType)
    {
        format = [self getFormatString:pixelFormatType];
    }
    return format;
}

- (NSString*)activeResolution
{
    return [captureSession sessionPreset];
}

- (NSString*)activeScalingMode
{
    NSDictionary* videoSettings = [captureOutput videoSettings];
    NSString* scalingMode = [videoSettings objectForKey:AVVideoScalingModeKey];
    return scalingMode;
}

- (NSString*)activeFrameRate
{
    float maxFrameRate = 1.0 / CMTimeGetSeconds([captureDevice activeVideoMinFrameDuration]);
//    NSArray *videoSupportedFrameRateRanges = [[captureDevice activeFormat] videoSupportedFrameRateRanges];
//    AVFrameRateRange * frameRateRange = nil;
//    for(frameRateRange in videoSupportedFrameRateRanges)
//    {
//        if(0 == CMTimeCompare([captureDevice activeVideoMinFrameDuration], [frameRateRange minFrameDuration]))
//        {
//            maxFrameRate = [frameRateRange maxFrameRate];
//            break;
//        }
//    }
    
    return [NSString stringWithFormat:@"%.2f", maxFrameRate];
}

- (NSString*)activeDeviceFormat
{
    AVCaptureDeviceFormat *format = [captureDevice activeFormat];
    CMFormatDescriptionRef formatDescription = [format formatDescription];
    FourCharCode codecType = CMVideoFormatDescriptionGetCodecType(formatDescription);;
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
    return [NSString stringWithFormat:@"%@, %dx%d", NSFileTypeForHFSTypeCode(codecType), dimensions.width, dimensions.height];
}

- (NSString*)summaryInfo
{
    NSMutableString *summaryInfo = [NSMutableString stringWithCapacity:0];
    [summaryInfo appendFormat:@"Pixel Format Type: %@ [%@ - 0x%8x]", [self getFormatString:[NSNumber numberWithUnsignedInt:realPixelFormat]], NSFileTypeForHFSTypeCode(realPixelFormat), realPixelFormat];
    [summaryInfo appendFormat:@"\nResolution: %ld x %ld", realPixelWidth, realPixelHeight];
    [summaryInfo appendFormat:@"\nSession Preset: %@", [captureSession sessionPreset]];
    [summaryInfo appendFormat:@"\nFrame Rate: %d", realFrameRate];
    [summaryInfo appendFormat:@"\nFrame Count: %d", totalFrameCount];
    
    if(NO == bScreenCapture) {
        [summaryInfo appendFormat:@"\nDevice Active Info: %@ min FD = %f, max FD = %f", [captureDevice activeFormat], CMTimeGetSeconds([captureDevice activeVideoMinFrameDuration]), CMTimeGetSeconds([captureDevice activeVideoMaxFrameDuration])];
    }
    
//    [summaryInfo appendFormat:@"\nnCapture Layer Video Gravity: %@", [captureLayer videoGravity]];
    [summaryInfo appendFormat:@"\nCapture Layer Status: %@ - %@, hidden = %d", [self getCaptureLayerStatusString:[captureLayer status]], [captureLayer error], [self isCaptureLayerHidden]];
    
    return summaryInfo;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
#if USE_CAPTURE_LAYER
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    FourCharCode codecType = CMVideoFormatDescriptionGetCodecType(formatDescription);
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
    
    realPixelFormat = codecType;
    realPixelWidth = dimensions.width;
    realPixelHeight = dimensions.height;
    
    frameCount++;
    totalFrameCount++;
    
    [captureLayer enqueueSampleBuffer:sampleBuffer];
#else
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if(kCVReturnSuccess == CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly))
    {
        size_t extraColumnsOnLeft = -1, extraColumnsOnRight = -1, extraRowsOnTop = -1, extraRowsOnBottom = -1;
        CVPixelBufferGetExtendedPixels(imageBuffer,
                                       &extraColumnsOnLeft,
                                       &extraColumnsOnRight,
                                       &extraRowsOnTop,
                                       &extraRowsOnBottom);
        
        OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
        size_t pixelWidth = CVPixelBufferGetWidth(imageBuffer);
        size_t pixelHeight = CVPixelBufferGetHeight(imageBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        void* baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
//        size_t dataSize = CVPixelBufferGetDataSize(imageBuffer);
        size_t pixelSize = bytesPerRow * pixelHeight;
        Boolean isPlanar = CVPixelBufferIsPlanar(imageBuffer);
        size_t planeCount = CVPixelBufferGetPlaneCount(imageBuffer);
        void* planeAddress[MAX_PLANE_COUNT];
        size_t planeSize[MAX_PLANE_COUNT];
        if(true == isPlanar && planeCount > 0)
        {
//            CVPlanarPixelBufferInfo_YCbCrBiPlanar *pPlanarInfo = (CVPlanarPixelBufferInfo_YCbCrBiPlanar*)baseAddress;
            
            if(planeCount <= MAX_PLANE_COUNT)
            {
                size_t planeWidth = 0, planeHeight = 0, planeBytesPreRow = 0;
                for(int i = 0; i < planeCount; i++)
                {
                    planeAddress[i] = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, i);
                    planeWidth = CVPixelBufferGetWidthOfPlane(imageBuffer, i);
                    planeHeight = CVPixelBufferGetHeightOfPlane(imageBuffer, i);
                    planeBytesPreRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, i);
                    planeSize[i] = planeBytesPreRow * planeHeight;
                }
            }
            else 
            {
                NSLog(@"captured data is planar, but plane count is over MAX_PLANE_COUNT, pixelFormat = %u, planeCount = %lu", (unsigned)pixelFormat, planeCount);
                CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
                return;
            }
        }
        
        realPixelFormat = pixelFormat;
        realPixelWidth = pixelWidth;
        realPixelHeight = pixelHeight;
        
        frameCount++;
        totalFrameCount++;
        
        [self setCaptureLayerHidden:YES];
        if(true == isPlanar)
        {
            [captureView renderFrame:(unsigned char**)planeAddress Length:(int*)planeSize Count:(int)planeCount Width:(int)pixelWidth Height:(int)pixelHeight Format:pixelFormat];
        }
        else
        {
            [captureView renderFrame:(unsigned char**)&baseAddress Length:(int*)&pixelSize Count:1 Width:(int)pixelWidth Height:(int)pixelHeight Format:pixelFormat];
        }
        
//        NSLog(@"capture a sample, pixelFormat = %d, pixelWidth = %d, pixelHeight = %d, isPlanar = %d, planeCount = %d, extraColumnsOnLeft = %d, extraColumnsOnRight = %d, extraRowsOnTop = %d, extraRowsOnBottom = %d",
//              pixelFormat, pixelWidth, pixelHeight, isPlanar, planeCount, extraColumnsOnLeft, extraColumnsOnRight, extraRowsOnTop, extraRowsOnBottom);
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    }
    else
    {
        CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
        FourCharCode codecType = CMVideoFormatDescriptionGetCodecType(formatDescription);
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
        
        realPixelFormat = codecType;
        realPixelWidth = dimensions.width;
        realPixelHeight = dimensions.height;
        
        frameCount++;
        totalFrameCount++;
        
        [self setCaptureLayerHidden:NO];
        [captureLayer enqueueSampleBuffer:sampleBuffer];
    }
#endif
}

#pragma mark Methods for internal use
- (void)addObserversForDevices
{
    for(AVCaptureDevice *device in devicesArray)
    {
        [device addObserver:self forKeyPath:@"connected" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:nil];
        [device addObserver:self forKeyPath:@"suspended" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:nil];
        [device addObserver:self forKeyPath:@"inUseByAnotherApplication" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:nil];
        [device addObserver:self forKeyPath:@"activeFormat" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:nil];
        [device addObserver:self forKeyPath:@"activeVideoMinFrameDuration" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:nil];
        [device addObserver:self forKeyPath:@"activeVideoMaxFrameDuration" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:nil];
    }
}

- (void)removeObserversForDevices
{
    for(AVCaptureDevice *device in devicesArray)
    {
        [device removeObserver:self forKeyPath:@"connected"];
        [device removeObserver:self forKeyPath:@"suspended"];
        [device removeObserver:self forKeyPath:@"inUseByAnotherApplication"];
        [device removeObserver:self forKeyPath:@"activeFormat"];
        [device removeObserver:self forKeyPath:@"activeVideoMinFrameDuration"];
        [device removeObserver:self forKeyPath:@"activeVideoMaxFrameDuration"];
    }
}

- (void)updateCaptureDevices
{
    AVCaptureDevice *backCaptureDevice = [captureDevice retain];
    
    [self removeObserversForDevices];
    [devicesArray release];
    devicesArray = [[[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] arrayByAddingObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeMuxed]] retain];
    [self addObserversForDevices];
    if([devicesArray count] > 0)
    {
        if(YES == [devicesArray containsObject:captureDevice])
        {
            captureDeviceIndex = (int)[devicesArray indexOfObject:captureDevice];
        }
        else
        {
            captureDeviceIndex = -1;
            captureDevice = nil;
            [captuerDelegate deviceChangeWithType:AVCaptureDeviceChangeSelected];
        }
    }
    else
    {
        captureDeviceIndex = -1;
        captureDevice = nil;
    }
    
    [backCaptureDevice release];
}

- (void)updateFrameRate
{
    realFrameRate = frameCount;
    frameCount = 0;
}

- (void)getCaptureDeviceInfo
{
    // Device Characteristics
    NSString *localizedName = [captureDevice localizedName];
    NSString *modelID = [captureDevice modelID];
    NSString *uniqueID = [captureDevice uniqueID];
    AVCaptureDevicePosition position = [captureDevice position];
    BOOL connected = [captureDevice isConnected];
    BOOL suspended = [captureDevice isSuspended];
    BOOL inUseByAnotherApplication = [captureDevice isInUseByAnotherApplication];
    NSLog(@"Get device info: localizedName = %@, modelID = %@, uniqueID = %@, position = %d, connected = %d, suspended = %d, inUseByAnotherApplication = %d",
          localizedName, modelID, uniqueID, (int)position, connected, suspended, inUseByAnotherApplication);
    
    // Managing Device Configuration
    NSArray *inputSources = [captureDevice inputSources];
    NSArray *linkedDevices = [captureDevice linkedDevices];
    AVCaptureDeviceInputSource *activeInputSource = [captureDevice activeInputSource];
    NSString *manufacturer = [captureDevice manufacturer];
    int32_t transportType = [captureDevice transportType];//kIOAudioDeviceTransportTypePCI, kIOAudioDeviceTransportTypeUSB
    NSLog(@"device inputSources: %@,\n activeInputSource: %@,\n linkedDevices: %@,\n transportType: %@[%d],\n manufacturer: %@", inputSources, activeInputSource, linkedDevices, NSFileTypeForHFSTypeCode(transportType), transportType, manufacturer);
    
    // Managing Transport Controls
    BOOL transportControlsSupported = [captureDevice transportControlsSupported];
    AVCaptureDeviceTransportControlsPlaybackMode transportControlsPlaybackMode = AVCaptureDeviceTransportControlsNotPlayingMode;
    AVCaptureDeviceTransportControlsSpeed transportControlsSpeed = 0;
    if(YES == transportControlsSupported)
    {
        transportControlsPlaybackMode = [captureDevice transportControlsPlaybackMode];
        transportControlsSpeed = [captureDevice transportControlsSpeed];
    }
    
    // Managing Formats
    NSString *mediaType = nil;
    CMFormatDescriptionRef formatDescription = nil;
    NSArray *videoSupportedFrameRateRanges = nil;
    AVFrameRateRange * frameRateRange = nil;
    Float64 minFrameRate = 0.0, maxFrameRate = 0.0;
    CMTime minFrameDuration, maxFrameDuration;
    FourCharCode codecType = 0;
    CMVideoDimensions dimensions = {0, 0};
    CGSize presentationDimensions = CGSizeZero;
    CGRect cleanAperture = CGRectZero;

    NSArray *formats = [captureDevice formats];
    NSLog(@"device format array: %@", formats);
    AVCaptureDeviceFormat *deviceFormat = nil;
    for(deviceFormat in formats)
    {
        mediaType = [deviceFormat mediaType];
        formatDescription = [deviceFormat formatDescription];
        codecType = CMVideoFormatDescriptionGetCodecType(formatDescription);
        dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
        presentationDimensions = CMVideoFormatDescriptionGetPresentationDimensions(formatDescription, true, true);
        cleanAperture = CMVideoFormatDescriptionGetCleanAperture(formatDescription, false);
//        NSLog(@"format support: mediaType = %@, codecType = %@[%lu], dimensions = %d x %d", mediaType, NSFileTypeForHFSTypeCode(codecType), codecType, dimensions.width, dimensions.height);
        videoSupportedFrameRateRanges = [deviceFormat videoSupportedFrameRateRanges];
        for(frameRateRange in videoSupportedFrameRateRanges)
        {
            minFrameRate = [frameRateRange minFrameRate];
            maxFrameRate = [frameRateRange maxFrameRate];
            minFrameDuration = [frameRateRange minFrameDuration];
            maxFrameDuration = [frameRateRange maxFrameDuration];
//            NSLog(@"format support: minFrameRate = %f, maxFrameRate = %f, minFrameDuration = %f, maxFrameDuration = %f", minFrameRate, maxFrameRate, CMTimeGetSeconds(minFrameDuration) , CMTimeGetSeconds(maxFrameDuration));
        }
    }
    
    CMTime activeVideoMinFrameDuration = [captureDevice activeVideoMinFrameDuration];
    CMTime activeVideoMaxFrameDuration = [captureDevice activeVideoMaxFrameDuration];
    deviceFormat = [captureDevice activeFormat];
    mediaType = [deviceFormat mediaType];
    formatDescription = [deviceFormat formatDescription];
    codecType = CMVideoFormatDescriptionGetCodecType(formatDescription);
    dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
    presentationDimensions = CMVideoFormatDescriptionGetPresentationDimensions(formatDescription, true, true);
    cleanAperture = CMVideoFormatDescriptionGetCleanAperture(formatDescription, false);
    NSLog(@"active format: mediaType = %@, codecType = %@[%u], dimensions = %dx%d, minFrameDuration = %f, maxFrameDuration = %f",
          mediaType, NSFileTypeForHFSTypeCode(codecType), (unsigned)codecType, dimensions.width, dimensions.height, CMTimeGetSeconds(activeVideoMinFrameDuration), CMTimeGetSeconds(activeVideoMaxFrameDuration));
    videoSupportedFrameRateRanges = [deviceFormat videoSupportedFrameRateRanges];
    for(frameRateRange in videoSupportedFrameRateRanges)
    {
        minFrameRate = [frameRateRange minFrameRate];
        maxFrameRate = [frameRateRange maxFrameRate];
        minFrameDuration = [frameRateRange minFrameDuration];
        maxFrameDuration = [frameRateRange maxFrameDuration];
//        NSLog(@"active format: minFrameRate = %f, maxFrameRate = %f, minFrameDuration = %f, maxFrameDuration = %f", 
//              minFrameRate, maxFrameRate, CMTimeGetSeconds(minFrameDuration) , CMTimeGetSeconds(maxFrameDuration));
    }
    
    // Device Adavance Characteristics
    BOOL hasFlash = [captureDevice hasFlash];
    AVCaptureFlashMode falshMode = [captureDevice flashMode];
    BOOL hasTorch = [captureDevice hasTorch];
    AVCaptureTorchMode torchMode = [captureDevice torchMode];
    AVCaptureFocusMode focusMode = [captureDevice focusMode];
    AVCaptureExposureMode exposureMode = [captureDevice exposureMode];
    AVCaptureWhiteBalanceMode whiteBalanceMode = [captureDevice whiteBalanceMode];
    NSLog(@"Get device advance info: hasFlash = %d, falshMode = %d, hasTorch = %d, torchMode = %d, focusMode = %d, exposureMode = %d, whiteBalanceMode = %d",
          hasFlash, (int)falshMode, hasTorch, (int)torchMode, (int)focusMode, (int)exposureMode, (int)whiteBalanceMode);
}

- (void)setCaptureOutputInfo
{
    // set alwaysDiscardsLateVideoFrames property, default is YES
    BOOL alwaysDiscardsLateVideoFrames = [captureOutput alwaysDiscardsLateVideoFrames];
    NSLog(@"[setCaptureOutputInfo] Get alwaysDiscardsLateVideoFrames = %d", alwaysDiscardsLateVideoFrames);
    
    // set video settings
    NSDictionary* videoSettings = [captureOutput videoSettings];
    NSLog(@"[setCaptureOutputInfo] Get videoSettings before set: %@", videoSettings);

    NSMutableDictionary* newVideoSettings = [NSMutableDictionary dictionaryWithCapacity:0];
    if(nil != activePixelFormatType)
    {
        [newVideoSettings addEntriesFromDictionary:videoSettings];
        [newVideoSettings setObject:activePixelFormatType forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
        [newVideoSettings setObject:kScalingMode forKey:AVVideoScalingModeKey];
    }
    [captureOutput setVideoSettings:newVideoSettings];
    
    videoSettings = [captureOutput videoSettings];
    NSLog(@"[setCaptureOutputInfo] Get videoSettings after set: %@", videoSettings);
    
    // set connection properties
    NSArray *connections = [captureOutput connections];
    NSUInteger connectionCount = [connections count];
    if(connectionCount > 0)
    {
        AVCaptureConnection *connection = [connections objectAtIndex:0];

#if SET_CONNECTION_FPS
        // set frame rate, default is 30 fps
        if(YES == [connection respondsToSelector:@selector(isVideoMinFrameDurationSupported)])
        {
            BOOL supportsVideoMinFrameDuration = [connection isVideoMinFrameDurationSupported];
            if(YES == supportsVideoMinFrameDuration)
            {
                [connection setVideoMinFrameDuration: CMTimeMakeWithSeconds(1.0 / kFrameRate, 10000)];
            }
        }
        if(YES == [connection respondsToSelector:@selector(isVideoMaxFrameDurationSupported)])
        {
            BOOL supportsVideoMaxFrameDuration = [connection isVideoMaxFrameDurationSupported];
            if(YES == supportsVideoMaxFrameDuration)
            {
                [connection setVideoMaxFrameDuration: CMTimeMakeWithSeconds(1.0 / kFrameRate, 10000)];
            }
        }
#endif
        
        // set mirroring
        BOOL supportsVideoMirroring = [connection isVideoMirroringSupported];
        BOOL videoMirrored = [connection isVideoMirrored];
        BOOL automaticallyAdjustsVideoMirroring = [connection automaticallyAdjustsVideoMirroring];
        if(YES == supportsVideoMirroring)
        {
//            [connection setVideoMirrored:YES];
        }
        
        // set orientation
        BOOL supportsVideoOrientation = [connection isVideoOrientationSupported];
        AVCaptureVideoOrientation videoOrientation = [connection videoOrientation];
        if(YES == supportsVideoOrientation)
        {
//            [connection setVideoOrientation:AVCaptureVideoOrientationPortrait];
//            [connection setVideoOrientation:AVCaptureVideoOrientationLandscapeRight];
//            [connection setVideoOrientation:AVCaptureVideoOrientationPortraitUpsideDown];
//            [connection setVideoOrientation:AVCaptureVideoOrientationLandscapeLeft];
        }
        
        // set field mode
        BOOL supportsVideoFieldMode = [connection isVideoFieldModeSupported];
        AVVideoFieldMode videoFieldMode = [connection videoFieldMode];
        if(YES == supportsVideoFieldMode)
        {
//            [connection setVideoFieldMode:videoFieldMode];
        }
        
        NSLog(@"[setCaptureOutputInfo] Get connection info: support-mirror = %d, mirror = %d, automaticallyAdjustsVideoMirroring = %d, support-orientation = %d, orientation = %d, support-field-mode = %d, field-mode = %d",
              supportsVideoMirroring, videoMirrored, automaticallyAdjustsVideoMirroring, supportsVideoOrientation, (int)videoOrientation, supportsVideoFieldMode, (int)videoFieldMode);
    }
}


// pixel format type lsit 
/*
 kCVPixelFormatType_422YpCbCr8     = '2vuy',
 kCVPixelFormatType_422YpCbCr8_yuvs = 'yuvs',
 
 kCVPixelFormatType_32ARGB         = 0x00000020,
 kCVPixelFormatType_32BGRA         = 'BGRA',
 
 kCVPixelFormatType_24RGB          = 0x00000018,
 
 kCVPixelFormatType_16BE555        = 0x00000010,
 kCVPixelFormatType_16BE565        = 'B565',
 kCVPixelFormatType_16LE555        = 'L555',
 kCVPixelFormatType_16LE565        = 'L565',
 kCVPixelFormatType_16LE5551       = '5551',
 
 kCVPixelFormatType_444YpCbCr8     = 'v308',
 kCVPixelFormatType_4444YpCbCrA8   = 'v408',
 kCVPixelFormatType_422YpCbCr16    = 'v216',
 kCVPixelFormatType_422YpCbCr10    = 'v210',
 kCVPixelFormatType_444YpCbCr10    = 'v410',
 
 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange = '420v',
 kCVPixelFormatType_420YpCbCr8BiPlanarFullRange  = '420f',
 
 kCMVideoCodecType_JPEG_OpenDML    = 'dmb1',
*/

- (NSNumber*)getFormatNumber:(NSString*)formatString
{
    NSNumber *formatNumber = nil;
    
    if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_422YpCbCr8"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_422YpCbCr8];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_422YpCbCr8_yuvs"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_422YpCbCr8_yuvs];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_32ARGB"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32ARGB];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_32BGRA"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_24RGB"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_24RGB];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_16BE555"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_16BE555];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_16BE565"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_16BE565];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_16LE555"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_16LE555];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_16LE565"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_16LE565];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_16LE5551"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_16LE5551];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_444YpCbCr8"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_444YpCbCr8];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_4444YpCbCrA8"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_4444YpCbCrA8];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_422YpCbCr16"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_422YpCbCr16];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_422YpCbCr10"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_422YpCbCr10];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_444YpCbCr10"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_444YpCbCr10];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange];
    }
    else if(NSOrderedSame == [formatString compare:@"kCVPixelFormatType_420YpCbCr8BiPlanarFullRange"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
    }
    else if(NSOrderedSame == [formatString compare:@"kCMVideoCodecType_JPEG_OpenDML"])
    {
        formatNumber = [NSNumber numberWithUnsignedInt:kCMVideoCodecType_JPEG_OpenDML];
    }
    else 
    {
        NSLog(@"Get format number fail, format string = %@", formatString);
    }
    
    return formatNumber;
}

- (NSString*)getFormatString:(NSNumber*)formatNumber
{
    NSString *formatString = NULL;
    unsigned int formatValue = [formatNumber unsignedIntValue];
    switch(formatValue) {
        case kCVPixelFormatType_422YpCbCr8:
            formatString = @"kCVPixelFormatType_422YpCbCr8";
            break;
        case kCVPixelFormatType_422YpCbCr8_yuvs:
            formatString = @"kCVPixelFormatType_422YpCbCr8_yuvs";
            break;
        case kCVPixelFormatType_32ARGB:
            formatString = @"kCVPixelFormatType_32ARGB";
            break;
        case kCVPixelFormatType_32BGRA:
            formatString = @"kCVPixelFormatType_32BGRA";
            break;
        case kCVPixelFormatType_24RGB:
            formatString = @"kCVPixelFormatType_24RGB";
            break;
        case kCVPixelFormatType_16BE555:
            formatString = @"kCVPixelFormatType_16BE555";
            break;
        case kCVPixelFormatType_16BE565:
            formatString = @"kCVPixelFormatType_16BE565";
            break;
        case kCVPixelFormatType_16LE555:
            formatString = @"kCVPixelFormatType_16LE555";
            break;
        case kCVPixelFormatType_16LE565:
            formatString = @"kCVPixelFormatType_16LE565";
            break;
        case kCVPixelFormatType_16LE5551:
            formatString = @"kCVPixelFormatType_16LE5551";
            break;
        case kCVPixelFormatType_444YpCbCr8:
            formatString = @"kCVPixelFormatType_444YpCbCr8";
            break;
        case kCVPixelFormatType_4444YpCbCrA8:
            formatString = @"kCVPixelFormatType_4444YpCbCrA8";
            break;
        case kCVPixelFormatType_422YpCbCr16:
            formatString = @"kCVPixelFormatType_422YpCbCr16";
            break;
        case kCVPixelFormatType_422YpCbCr10:
            formatString = @"kCVPixelFormatType_422YpCbCr10";
            break;
        case kCVPixelFormatType_444YpCbCr10:
            formatString = @"kCVPixelFormatType_444YpCbCr10";
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            formatString = @"kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange";
            break;
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            formatString = @"kCVPixelFormatType_420YpCbCr8BiPlanarFullRange";
            break;
        case kCMVideoCodecType_JPEG_OpenDML:
            formatString = @"kCMVideoCodecType_JPEG_OpenDML";
            break;
            
        default:
            NSLog(@"Get format string fail, format number = %@", formatNumber);
            formatString = [NSString stringWithFormat:@"UnknownFormatType_%@", formatNumber];
            break;
    }
    
    return formatString;
}

- (NSSize)getResolutionSize:(NSString*)sessionPreset
{
    NSSize resolutionSize = NSZeroSize;
    
    if(NSOrderedSame == [sessionPreset compare:AVCaptureSessionPreset1280x720])
    {
        resolutionSize.width = 1280;
        resolutionSize.height = 720;
    }
    else if(NSOrderedSame == [sessionPreset compare:AVCaptureSessionPreset960x540])
    {
        resolutionSize.width = 960;
        resolutionSize.height = 540;
    }
    else if(NSOrderedSame == [sessionPreset compare:AVCaptureSessionPreset640x480])
    {
        resolutionSize.width = 640;
        resolutionSize.height = 480;
    }
    else if(NSOrderedSame == [sessionPreset compare:AVCaptureSessionPreset352x288])
    {
        resolutionSize.width = 352;
        resolutionSize.height = 288;
    }
    else if(NSOrderedSame == [sessionPreset compare:AVCaptureSessionPreset320x240])
    {
        resolutionSize.width = 320;
        resolutionSize.height = 240;
    }
    
    return resolutionSize;
}

- (NSString*)getCaptureLayerStatusString:(AVQueuedSampleBufferRenderingStatus)status
{
    NSString *statusString = NULL;
    switch (status) {
        case AVQueuedSampleBufferRenderingStatusRendering:
            statusString = @"AVQueuedSampleBufferRenderingStatusRendering";
            break;
            
        case AVQueuedSampleBufferRenderingStatusFailed:
            statusString = @"AVQueuedSampleBufferRenderingStatusFailed";
            break;
            
        case AVQueuedSampleBufferRenderingStatusUnknown:
        default:
            statusString = @"AVQueuedSampleBufferRenderingStatusUnknown";
            break;
    }
    
    return statusString;
}

- (BOOL)isCaptureLayerHidden
{
    BOOL isHidden = (YES == captureLayer.hidden || NO == [[[captureView layer] sublayers] containsObject:captureLayer]);
    return isHidden;
}

- (void)setCaptureLayerHidden:(BOOL)hidden
{
#if ENABLE_REMOVE_LAYER
    BOOL contain = [[[captureView layer] sublayers] containsObject:captureLayer];
    if (YES == hidden && YES == contain) {
        [captureLayer removeFromSuperlayer];
    } else if (NO == hidden && NO == contain) {
        captureLayer.frame = captureView.bounds;
        [[captureView layer] addSublayer:captureLayer];
        [captureLayer flush];
    }
#else
    captureLayer.hidden = hidden;
#endif
}

@end
