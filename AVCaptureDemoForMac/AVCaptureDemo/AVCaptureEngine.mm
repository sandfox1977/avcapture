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

- (void)updateCaptureDevices;
- (void)updateFrameRate;

- (void)getCaptureDeviceInfo;
- (void)setCaptureOutputInfo;

- (NSNumber*)getFormatNumber:(NSString*)formatString;
- (NSString*)getFormatString:(NSNumber*)formatNumber;

- (NSSize)getResolutionSize:(NSString*)sessionPreset;

@end

@implementation AVCaptureEngine

- (id)initWithView:(NSView*)pView CaptureView:(AVCaptureView*)cView
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
    }
    
    return self;
}

- (void)dealloc
{
    [fpsTimer invalidate];
    fpsTimer = nil;
    
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
    
    [devicesArray release];
    
    // remove observers
	NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
	for (id observer in observers)
		[notificationCenter removeObserver:observer];
	[observers release];
    
    [super dealloc];
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

- (void)setFormat:(NSString*)format
{
    NSNumber *pixelFormatType = [self getFormatNumber:format];
    if(nil == pixelFormatType)
    {
        return;
    }
    
    activePixelFormatType = pixelFormatType;
    
    NSDictionary* videoSettings = [captureOutput videoSettings];
    NSLog(@"[setFormat] Get videoSettings before set: %@", videoSettings);
    
    NSMutableDictionary* newVideoSettings = [NSMutableDictionary dictionaryWithCapacity:0];
    [newVideoSettings addEntriesFromDictionary:videoSettings];
    [newVideoSettings setObject:activePixelFormatType forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
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
    [newVideoSettings addEntriesFromDictionary:videoSettings];
    [newVideoSettings setObject:activePixelFormatType forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
    [newVideoSettings setObject:kScalingMode forKey:AVVideoScalingModeKey];
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
    [newVideoSettings addEntriesFromDictionary:videoSettings];
    [newVideoSettings setObject:activeScalingMode forKey:AVVideoScalingModeKey];
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
    
    NSArray *videoSupportedFrameRateRanges = [[captureDevice activeFormat] videoSupportedFrameRateRanges];
    AVFrameRateRange * frameRateRange = [videoSupportedFrameRateRanges objectAtIndex:index];
    NSError *error = nil;
    if(nil != frameRateRange && YES == [captureDevice lockForConfiguration:&error])
    {
        [captureDevice setActiveVideoMinFrameDuration:[frameRateRange minFrameDuration]];
        [captureDevice setActiveVideoMaxFrameDuration:[frameRateRange maxFrameDuration]];
        [captureDevice unlockForConfiguration];
        NSLog(@"[setFrameRate] set new frame rate: %@, index = %d", frameRateRange, (int)index);
    }
    else
    {
        NSLog(@"[setFrameRate] set new frame rate fail: %@, error: %@", frameRateRange, error);
    }
}

- (NSString*)activeFormat
{
    NSDictionary* videoSettings = [captureOutput videoSettings];
    NSNumber* pixelFormatType = [videoSettings objectForKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
    return [self getFormatString:pixelFormatType];
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
    NSString *frameRate = [NSString stringWithFormat:@"%.2f", maxFrameRate];
    return frameRate;
}

- (NSString*)summaryInfo
{
    NSMutableString *summaryInfo = [NSMutableString stringWithCapacity:0];
    [summaryInfo appendFormat:@"Pixel Format Type: %@", [self getFormatString:[NSNumber numberWithUnsignedInt:realPixelFormat]]];
    [summaryInfo appendString:@"\n"];
    [summaryInfo appendFormat:@"Resolution: %ld x %ld", realPixelWidth, realPixelHeight];
    [summaryInfo appendString:@"\n"];
    [summaryInfo appendFormat:@"Session Preset: %@", [captureSession sessionPreset]];
    [summaryInfo appendString:@"\n"];
//    [summaryInfo appendFormat:@"Preview Video Gravity: %@", [captureLayer videoGravity]];
//    [summaryInfo appendString:@"\n"];
    [summaryInfo appendFormat:@"Frame Rate: %d", realFrameRate];
    [summaryInfo appendString:@"\n"];
    [summaryInfo appendFormat:@"Frame Count: %d", totalFrameCount];
    [summaryInfo appendString:@"\n"];
    
    if(NO == bScreenCapture) {
        [summaryInfo appendFormat:@"Device Active Info: %@ min FD = %f, max FD = %f", [captureDevice activeFormat], CMTimeGetSeconds([captureDevice activeVideoMinFrameDuration]), CMTimeGetSeconds([captureDevice activeVideoMaxFrameDuration])];
    }
    
    return summaryInfo;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
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
        size_t dataSize = CVPixelBufferGetDataSize(imageBuffer);
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
}

#pragma mark Methods for internal use
@class AppDelegate;
- (void)updateCaptureDevices
{
    AVCaptureDevice *backCaptureDevice = [captureDevice retain];
    
    [devicesArray release];
    devicesArray = [[[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] arrayByAddingObjectsFromArray:[AVCaptureDevice devicesWithMediaType:AVMediaTypeMuxed]] retain];
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
            [(AppDelegate*)[[NSApplication sharedApplication] delegate] clickSwitchButton:nil];
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
    int32_t transportType = [captureDevice transportType];//kIOAudioDeviceTransportType
//    NSLog(@"device inputSources: %@,\n activeInputSource: %@,\n linkedDevices: %@,\n transportType: %d", inputSources, activeInputSource, linkedDevices, transportType);
    
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
    [newVideoSettings addEntriesFromDictionary:videoSettings];
    [newVideoSettings setObject:activePixelFormatType forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
    [newVideoSettings setObject:kScalingMode forKey:AVVideoScalingModeKey];
    [captureOutput setVideoSettings:newVideoSettings];
    
    videoSettings = [captureOutput videoSettings];
    NSLog(@"[setCaptureOutputInfo] Get videoSettings after set: %@", videoSettings);
    
    // set connection properties
    NSArray *connections = [captureOutput connections];
    NSUInteger connectionCount = [connections count];
    if(connectionCount > 0)
    {
        AVCaptureConnection *connection = [connections objectAtIndex:0];
        
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

@end
