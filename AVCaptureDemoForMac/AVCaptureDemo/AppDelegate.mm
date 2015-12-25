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
@synthesize frameRateButton;
@synthesize deviceFormatButton;

- (void)dealloc
{
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    [previewView setWantsLayer:YES];
    
    captureEngine = [[AVCaptureEngine alloc] initWithView:previewView CaptureView:captureView];
    [captureEngine setDelegate:self];
    
    [deviceName setTitleWithMnemonic:[captureEngine currentDeviceName]];
    
    [formatButton removeAllItems];
    [formatButton addItemsWithTitles:[captureEngine allFormats]];
    [formatButton selectItemWithTitle:[captureEngine activeFormat]];
    
    [resolutionButton removeAllItems];
    [resolutionButton addItemsWithTitles:[captureEngine allResolutions]];
    [resolutionButton selectItemWithTitle:[captureEngine activeResolution]];
    
    [scalingButton removeAllItems];
    [scalingButton addItemsWithTitles:[captureEngine allScalingModes]];
    [scalingButton selectItemWithTitle:[captureEngine activeScalingMode]];
    
    [deviceFormatButton removeAllItems];
    [deviceFormatButton addItemsWithTitles:[captureEngine allDeviceFormats]];
    [deviceFormatButton selectItemWithTitle:[captureEngine activeDeviceFormat]];
    
    [frameRateButton removeAllItems];
    [frameRateButton addItemsWithTitles:[captureEngine allFrameRates]];
    [frameRateButton selectItemWithTitle:[captureEngine activeFrameRate]];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[captureEngine release];
}

- (void)deviceChangeWithType:(AVCaptureDeviceChangeType)type
{
    switch (type) {
        case AVCaptureDeviceChangeSelected:
            [self clickSwitchButton:nil];
            break;
            
        case AVCaptureDeviceChangeActiveFormat:
            [deviceFormatButton removeAllItems];
            [deviceFormatButton addItemsWithTitles:[captureEngine allDeviceFormats]];
            [deviceFormatButton selectItemWithTitle:[captureEngine activeDeviceFormat]];
            break;
            
        case AVCaptureDeviceChangeActiveFrameRate:
            [frameRateButton removeAllItems];
            [frameRateButton addItemsWithTitles:[captureEngine allFrameRates]];
            [frameRateButton selectItemWithTitle:[captureEngine activeFrameRate]];
            break;
            
        default:
            break;
    }
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
    [formatButton addItemsWithTitles:[captureEngine allFormats]];
    [formatButton selectItemWithTitle:[captureEngine activeFormat]];
    
    [resolutionButton removeAllItems];
    [resolutionButton addItemsWithTitles:[captureEngine allResolutions]];
    [resolutionButton selectItemWithTitle:[captureEngine activeResolution]];
    
    [deviceFormatButton removeAllItems];
    [deviceFormatButton addItemsWithTitles:[captureEngine allDeviceFormats]];
    [deviceFormatButton selectItemWithTitle:[captureEngine activeDeviceFormat]];
    
    [frameRateButton removeAllItems];
    [frameRateButton addItemsWithTitles:[captureEngine allFrameRates]];
    [frameRateButton selectItemWithTitle:[captureEngine activeFrameRate]];
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

- (IBAction)clickFrameRateButton:(id)sender
{
    [captureEngine setFrameRate:[frameRateButton titleOfSelectedItem] Index:[frameRateButton indexOfSelectedItem]];
}

- (IBAction)clickDeviceFormatButton:(id)sender
{
    [captureEngine setDeviceFormat:[deviceFormatButton titleOfSelectedItem] Index:[deviceFormatButton indexOfSelectedItem]];
}

- (void)checkStatus
{
    [summaryInfo setTitleWithMnemonic:[captureEngine summaryInfo]];
}

@end
