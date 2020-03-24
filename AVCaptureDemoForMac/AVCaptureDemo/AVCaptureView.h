//
//  AVCaptureView.h
//  AVCaptureDemo
//
//  Created by Sand Pei on 12-12-19.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <ApplicationServices/ApplicationServices.h>

#if 0

#import <OpenGL/glu.h>

@interface MyAVCaptureView : NSOpenGLView
{
    GLsizei	m_width;  
	GLsizei	m_height;
	
	GLsizei	m_imageBufferSize;
	GLvoid*	m_imageBuffer;
    
    GLsizei	m_roundBufferSize;
	GLvoid*	m_roundBuffer;
	
	GLuint	m_textureID;
	GLfloat	m_textureRoundedWidth;
	GLfloat	m_textureRoundedHeight;
    
    NSRecursiveLock*	m_lock;
}

- (int)renderFrame:(unsigned char* [])data Length:(int [])len Count:(int)count Width:(int)width Height:(int)height Format:(OSType)pixelFormat;

@end

#else

@interface MyAVCaptureView : NSView
{
    NSImageRep*         m_imageRep;
    int                 m_imageWidth;
    int                 m_imageHeight;
    NSRecursiveLock*	m_lock;
    
    unsigned char*      m_rgb24Buffer;
    int                 m_rgb24BufferSize;
}

- (int)renderFrame:(unsigned char**)data Length:(int*)len Count:(int)count Width:(int)width Height:(int)height Format:(OSType)pixelFormat;

@end

#endif
