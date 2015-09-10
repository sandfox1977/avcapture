//
//  AppDelegate.m
//  AVCaptureDemo
//
//  Created by Sand Pei on 12-4-17.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "AppDelegate.h"

@implementation AppDelegate

//@synthesize window = _window;
@synthesize window;
@synthesize previewView;
@synthesize captureView;
@synthesize summaryInfo;
@synthesize deviceName;
@synthesize formatButton;
@synthesize resolutionButton;
@synthesize scalingButton;

- (void)dealloc
{
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    [previewView setWantsLayer:YES];
    
    captureEngine = [[AVCaptureEngine alloc] initWithView:previewView CaptureView:captureView];
    
    [deviceName setTitleWithMnemonic:[captureEngine currentDeviceName]];
    
    [formatButton removeAllItems];
    NSArray *allFormats = [captureEngine allFormats];
    for(NSString* format in allFormats)
    {
        [formatButton addItemWithTitle:format];
    }
    [formatButton selectItemWithTitle:[captureEngine activeFormat]];
    
    [resolutionButton removeAllItems];
    NSArray *allResolutions = [captureEngine allResolutions];
    for(NSString* resolution in allResolutions)
    {
        [resolutionButton addItemWithTitle:resolution];
    }
    [resolutionButton selectItemWithTitle:[captureEngine activeResolution]];
    
    [scalingButton removeAllItems];
    NSArray *allScalingModes = [captureEngine allScalingModes];
    for(NSString* scalingMode in allScalingModes)
    {
        [scalingButton addItemWithTitle:scalingMode];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[captureEngine release];
}

- (IBAction)clickStartButton:(id)sender
{
	[captureEngine startRunning];
    
    checkTimer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)(1.0 / 30.0) target:self selector:@selector(checkStatus) userInfo:NULL repeats:YES];
}

- (IBAction)clickStopButton:(id)sender
{
	[checkTimer invalidate];
    checkTimer = NULL;
    
    [summaryInfo setTitleWithMnemonic:@""];
    
    [captureEngine stopRunning];
}

- (IBAction)clickSwitchButton:(id)sender
{
	[captureEngine switchDevice];
    
	[deviceName setTitleWithMnemonic:[captureEngine currentDeviceName]];
    
    [formatButton removeAllItems];
    NSArray *allFormats = [captureEngine allFormats];
    for(NSString* format in allFormats)
    {
        [formatButton addItemWithTitle:format];
    }
    [formatButton selectItemWithTitle:[captureEngine activeFormat]];
    
    [resolutionButton removeAllItems];
    NSArray *allResolutions = [captureEngine allResolutions];
    for(NSString* resolution in allResolutions)
    {
        [resolutionButton addItemWithTitle:resolution];
    }
    [resolutionButton selectItemWithTitle:[captureEngine activeResolution]];
}

- (IBAction)clickFormatButton:(id)sender
{
    [captureEngine setFormat:[formatButton titleOfSelectedItem]];
}

- (IBAction)clickResolutionButton:(id)sender
{
    [captureEngine setResolution:[resolutionButton titleOfSelectedItem]];
}

- (IBAction)clickScalingButton:(id)sender
{
    [captureEngine setScalingMode:[scalingButton titleOfSelectedItem]];
}

- (IBAction)clickScreenButton:(id)sender
{
    [captureEngine swtichScreenCapture];
}

- (IBAction)clickInfoButton:(id)sender
{
    [captureEngine printDeviceInfo];
}

- (void)checkStatus
{
    [summaryInfo setTitleWithMnemonic:[captureEngine summaryInfo]];
}

@end
