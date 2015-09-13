//
//  AVCaptureEngine.h
//  AVCaptureDemo
//
//  Created by Sand Pei on 12-4-13.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <ApplicationServices/ApplicationServices.h>

#import "AVCaptureView.h"

@interface AVCaptureEngine : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
{
@private
	NSArray *devicesArray;
	AVCaptureDevice *captureDevice;
	int captureDeviceIndex;
	
	AVCaptureSession *captureSession;
	AVCaptureDeviceInput *captureInput;
    AVCaptureScreenInput *screenInput;
    AVCaptureVideoDataOutput *captureOutput;
    BOOL bScreenCapture;
    
    NSView *previewView;
    AVCaptureVideoPreviewLayer *previewLayer;
	
	CVPixelBufferRef currentPixelBuffer;
    
    NSNumber *activePixelFormatType;
    NSString *activeResolution;
    NSString *activeScalingMode;
    
    OSType realPixelFormat;
    size_t realPixelWidth;
    size_t realPixelHeight;
    int realFrameRate;
    
    NSArray *observers;
    
    NSTimer *fpsTimer;
    int frameCount;
    int totalFrameCount;
    
    AVCaptureView *captureView;
}

- (id)initWithView:(NSView*)pView CaptureView:(AVCaptureView*)cView;

- (BOOL)isRunning;
- (void)startRunning;
- (void)stopRunning;

- (void)switchDevice;
- (void)swtichScreenCapture;

- (void)printDeviceInfo;

- (NSString*)currentDeviceName;
- (NSArray*)allFormats;
- (NSArray*)allCodecTypes;
- (NSArray*)allResolutions;
- (NSArray*)allScalingModes;
- (NSArray*)allFrameRates;
- (NSArray*)allDeviceFormats;
- (void)setFormat:(NSString*)format;
- (void)setResolution:(NSString*)resolution;
- (void)setScalingMode:(NSString*)scalingMode;
- (void)setFrameRate:(NSString*)frameRate Index:(NSInteger)index;
- (void)setDeviceFormat:(NSString*)deviceFormat Index:(NSInteger)index;
- (NSString*)activeFormat;
- (NSString*)activeResolution;
- (NSString*)activeScalingMode;
- (NSString*)activeFrameRate;
- (NSString*)activeDeviceFormat;
- (NSString*)summaryInfo;

@end
