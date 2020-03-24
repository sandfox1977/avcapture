//
//  AVCaptureView.m
//  AVCaptureDemo
//
//  Created by Sand Pei on 12-12-19.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "AVCaptureView.h"

#if 0

@implementation MyAVCaptureView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (id)initWithFrame:(NSRect)frameRect pixelFormat:(NSOpenGLPixelFormat*)format
{
    self = [super initWithFrame:frameRect pixelFormat:format];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    m_width = 0;
	m_height = 0;
	m_imageBufferSize = 0;
	m_imageBuffer = nil;
	m_roundBufferSize = 0;
	m_roundBuffer = nil;
	
	m_textureID = 0;
	m_textureRoundedWidth = 0;
	m_textureRoundedHeight = 0;
    
    m_lock = [[NSRecursiveLock alloc] init];
    
    self = [super initWithCoder:aDecoder];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)dealloc
{
    if (m_lock)
	{
		[m_lock release];
		m_lock = nil;
	}
    
    [[self openGLContext] makeCurrentContext];
    
    if(m_textureID)
	{
		glDeleteTextures(1, &m_textureID);
		m_textureID = 0;
	}
    
    [NSOpenGLContext clearCurrentContext];
    
    [super dealloc];
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Drawing code here.
//    NSRect bounds = [self bounds];
//	[[NSColor clearColor] set];
//    NSRectFill(bounds);
    
    [[self openGLContext] makeCurrentContext];
    
    NSRect bounds = [self bounds];
	
    // draw background
    glViewport(0, 0, bounds.size.width, bounds.size.height);
    
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(0, 1, 0, 1, 1.0, -1.0);
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();
    glClearColor(0, 0, 0, 1);
	glClear(GL_COLOR_BUFFER_BIT);
    
    // draw frame
    if([m_lock tryLock])
    {
        float viewWidth = bounds.size.width, viewHeight = bounds.size.height;
		float viewRatio = viewWidth / (float)viewHeight;
		float frameRatio = m_width / (float)m_height;
		if(viewRatio != frameRatio)
		{
            if(viewRatio > frameRatio)
            {
                bounds.size.width = (int)(viewHeight * frameRatio);
                bounds.origin.x = (int)((viewWidth - bounds.size.width + 1) / 2);
            }
            else
            {
                bounds.size.height = (int)(viewWidth / frameRatio);
                bounds.origin.y = (int)((viewHeight - bounds.size.height + 1) / 2);
            }
		}
        glViewport(0, 0, bounds.size.width, bounds.size.height);
        
        glEnable(GL_TEXTURE_2D);
        glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
        glEnable(GL_BLEND);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
        if(m_textureID)
        {
            glBindTexture(GL_TEXTURE_2D, m_textureID);
            glBegin(GL_POLYGON);
            {
                glTexCoord2f (m_textureRoundedWidth, m_textureRoundedHeight); 
                glVertex2f (1.0, 0.0);
                glTexCoord2f (0.0f, m_textureRoundedHeight); 
                glVertex2f (0.0, 0.0);
                glTexCoord2f (0.0f, 0.0f); 
                glVertex2f (0.0, 1.0);
                glTexCoord2f (m_textureRoundedWidth, 0.0f); 
                glVertex2f (1.0, 1.0);
            }
            glEnd();
            glBindTexture(GL_TEXTURE_2D, 0);
        }
        glDisable(GL_TEXTURE_2D);
        
        [m_lock unlock];
    }
    
    [[self openGLContext] flushBuffer];
    [NSOpenGLContext clearCurrentContext];
}

- (int)renderFrame:(unsigned char*)data Length:(int)len Width:(int)width Height:(int)height Format:(OSType)pixelFormat
{
    if([m_lock tryLock])
    {
        [[self openGLContext] makeCurrentContext];
        
        if(m_textureID == 0)
        {
            glGenTextures(1, &m_textureID);
            if(m_textureID == 0)
            {
                return -1;
            }
        }
        
        GLuint glFormat = GL_RGB;
        GLuint glType = GL_UNSIGNED_BYTE;
        if(kCVPixelFormatType_422YpCbCr8 == pixelFormat)
        {
            glFormat = GL_YCBCR_422_APPLE;
            glType = GL_UNSIGNED_SHORT_8_8_APPLE;
        }
        else if(kCVPixelFormatType_422YpCbCr8_yuvs == pixelFormat)
        {
            glFormat = GL_YCBCR_422_APPLE;
            glType = GL_UNSIGNED_SHORT_8_8_REV_APPLE;
        }
        else if(kCVPixelFormatType_32BGRA == pixelFormat)
        {
            glFormat = GL_BGRA;
            glType = GL_UNSIGNED_BYTE;
        }
        else if(kCVPixelFormatType_32ARGB == pixelFormat)
        {
            glFormat = GL_RGBA;
            glType = GL_UNSIGNED_BYTE;
        }
        
        m_width = width;
        m_height = height;
        
        NSRect bounds = [self bounds];
        float viewWidth = bounds.size.width, viewHeight = bounds.size.height;
		float viewRatio = viewWidth / (float)viewHeight;
		float frameRatio = m_width / (float)m_height;
		if(viewRatio != frameRatio)
		{
            if(viewRatio > frameRatio)
            {
                bounds.size.width = (int)(viewHeight * frameRatio);
                bounds.origin.x = (int)((viewWidth - bounds.size.width + 1) / 2);
            }
            else
            {
                bounds.size.height = (int)(viewWidth / frameRatio);
                bounds.origin.y = (int)((viewHeight - bounds.size.height + 1) / 2);
            }
		}
        
        glViewport(bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);kCGBitmapByteOrder32Little
        
        glPixelZoom(1.0, 1.0);
        glRasterPos2f(0.0, 0.0);
        glDrawPixels(width, height, glFormat, glType, data);
        
        GLsizei round_width = 1;
        GLsizei round_height = 1;	
        while((round_width *= 2) < width);
        while((round_height *= 2) < height);					
        if (round_width && round_height)
        {
            float w = width - 0.5;
            float h = height - 0.5;
            float rw = round_width;
            float rh = round_height;
            m_textureRoundedWidth = w/rw;
            m_textureRoundedHeight = h/rh;
        }
        else
        {
            m_textureRoundedWidth = 1.0;
            m_textureRoundedHeight = 1.0;
        }
        
    //	glDisable(GL_TEXTURE_2D);
        glPixelStorei( GL_UNPACK_ALIGNMENT, 1 );
        glBindTexture( GL_TEXTURE_2D, m_textureID );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR );
        glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR );
        glCopyTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, bounds.origin.x, bounds.origin.y, round_width, round_height, 0);
        
        [NSOpenGLContext clearCurrentContext];
        
        [m_lock unlock];
        
        [self performSelectorOnMainThread:@selector(reDisplayinMainThread) withObject:self waitUntilDone:NO];
    }
    
    return 0;
}

- (void)reDisplayinMainThread
{
	[self setNeedsDisplay:YES];
}

@end

#else

int convert_yuv_to_rgb_pixel(int y, int u, int v)
{
    unsigned int pixel32 = 0;
    unsigned char *pixel = (unsigned char *)&pixel32;
    int r, g, b;
    r = y + (1.370705 * (v-128));
    g = y - (0.698001 * (v-128)) - (0.337633 * (u-128));
    b = y + (1.732446 * (u-128));
    if(r > 255) r = 255;
    if(g > 255) g = 255;
    if(b > 255) b = 255;
    if(r < 0) r = 0;
    if(g < 0) g = 0;
    if(b < 0) b = 0;
    pixel[0] = r ;
    pixel[1] = g ;
    pixel[2] = b ;
    return pixel32;
}

int convert_yuv422_to_rgb24_buffer(unsigned char *yuv, unsigned char *rgb, unsigned int width, unsigned int height, bool rev)
{
    unsigned int in, out = 0;
    unsigned int pixel_16;
    unsigned char pixel_24[3];
    unsigned int pixel32;
    int y0, u, y1, v;
    
    for(in = 0; in < width * height * 2; in += 4)
    {
        pixel_16 =
        yuv[in + 3] << 24 |
        yuv[in + 2] << 16 |
        yuv[in + 1] <<  8 |
        yuv[in + 0];
        if(true == rev)
        {
            y0 = (pixel_16 & 0x000000ff);
            u  = (pixel_16 & 0x0000ff00) >>  8;
            y1 = (pixel_16 & 0x00ff0000) >> 16;
            v  = (pixel_16 & 0xff000000) >> 24;
        }
        else
        {
            u  = (pixel_16 & 0x000000ff);
            y0 = (pixel_16 & 0x0000ff00) >>  8;
            v  = (pixel_16 & 0x00ff0000) >> 16;
            y1 = (pixel_16 & 0xff000000) >> 24;
        }
        pixel32 = convert_yuv_to_rgb_pixel(y0, u, v);
        pixel_24[0] = (pixel32 & 0x000000ff);
        pixel_24[1] = (pixel32 & 0x0000ff00) >> 8;
        pixel_24[2] = (pixel32 & 0x00ff0000) >> 16;
        rgb[out++] = pixel_24[0];
        rgb[out++] = pixel_24[1];
        rgb[out++] = pixel_24[2];
        pixel32 = convert_yuv_to_rgb_pixel(y1, u, v);
        pixel_24[0] = (pixel32 & 0x000000ff);
        pixel_24[1] = (pixel32 & 0x0000ff00) >> 8;
        pixel_24[2] = (pixel32 & 0x00ff0000) >> 16;
        rgb[out++] = pixel_24[0];
        rgb[out++] = pixel_24[1];
        rgb[out++] = pixel_24[2];
    }
    return 0;
    
}

int convert_y420nv_to_rgb24_buffer(unsigned char *y, unsigned char *uv, unsigned char *rgb, unsigned int width, unsigned int height, bool rev)
{
    unsigned int iny, inuv, out = 0;
    unsigned char pixel_24[3];
    unsigned int pixel32;
    int y0, u, y1, v;
    
    for(iny = 0, inuv = 0; iny < width * height; iny += 2, inuv = (iny / width) / 2 * width + (iny % width))
    {
        if(true == rev)
        {
            y0 = y[iny + 0];
            y1 = y[iny + 1];
            v  = uv[inuv + 0];
            u  = uv[inuv + 1];
        }
        else
        {
            y0 = y[iny + 0];
            y1 = y[iny + 1];
            u  = uv[inuv + 0];
            v  = uv[inuv + 1];
        }
        pixel32 = convert_yuv_to_rgb_pixel(y0, u, v);
        pixel_24[0] = (pixel32 & 0x000000ff);
        pixel_24[1] = (pixel32 & 0x0000ff00) >> 8;
        pixel_24[2] = (pixel32 & 0x00ff0000) >> 16;
        rgb[out++] = pixel_24[0];
        rgb[out++] = pixel_24[1];
        rgb[out++] = pixel_24[2];
        pixel32 = convert_yuv_to_rgb_pixel(y1, u, v);
        pixel_24[0] = (pixel32 & 0x000000ff);
        pixel_24[1] = (pixel32 & 0x0000ff00) >> 8;
        pixel_24[2] = (pixel32 & 0x00ff0000) >> 16;
        rgb[out++] = pixel_24[0];
        rgb[out++] = pixel_24[1];
        rgb[out++] = pixel_24[2];
    }
    return 0;
    
}

@implementation MyAVCaptureView

- (id)initWithFrame:(NSRect)frame
{
    m_imageRep = NULL;
    m_lock = NULL;
    
    m_rgb24Buffer = NULL;
    m_rgb24BufferSize = 0;
    
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
        
        m_lock = [[NSRecursiveLock alloc] init];
        
    }
    
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    m_imageRep = NULL;
    m_lock = NULL;
    
    m_rgb24Buffer = NULL;
    m_rgb24BufferSize = 0;
    
    self = [super initWithCoder:aDecoder];
    if (self) {
        // Initialization code here.
        
        m_lock = [[NSRecursiveLock alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    [m_imageRep release];
    m_imageRep = NULL;
    
    [m_lock release];
    m_lock = NULL;
    
    if(m_rgb24Buffer)
    {
        delete[] m_rgb24Buffer;
        m_rgb24Buffer = NULL;
    }
    m_rgb24BufferSize = 0;
    
    [super dealloc];
}

- (int)renderFrame:(unsigned char**)data Length:(int*)len Count:(int)count Width:(int)width Height:(int)height Format:(OSType)pixelFormat
{
    unsigned char *rgbBuffer = NULL;
    int sampleBits = 8;
    int pixelSamples = 3;
    BOOL hasAlpha = NO;
    BOOL isPlanar = NO;
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaNone;
    
    if(kCVPixelFormatType_422YpCbCr8 == pixelFormat)
    {
        if(width * height * 3 > m_rgb24BufferSize)
        {
            if(m_rgb24Buffer)
            {
                delete[] m_rgb24Buffer;
            }
            m_rgb24BufferSize = width * height * 3;
            m_rgb24Buffer = new unsigned char[m_rgb24BufferSize];
        }
        convert_yuv422_to_rgb24_buffer((unsigned char *)data[0], m_rgb24Buffer, (unsigned int)width, (unsigned int)height, false);
        rgbBuffer = m_rgb24Buffer;
        sampleBits = 8;
        pixelSamples = 3;
        hasAlpha = NO;
        isPlanar = NO;
        bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaNone;
    }
    else if(kCVPixelFormatType_422YpCbCr8_yuvs == pixelFormat)
    {
        if(width * height * 3 > m_rgb24BufferSize)
        {
            if(m_rgb24Buffer)
            {
                delete[] m_rgb24Buffer;
            }
            m_rgb24BufferSize = width * height * 3;
            m_rgb24Buffer = new unsigned char[m_rgb24BufferSize];
        }
        convert_yuv422_to_rgb24_buffer((unsigned char *)data[0], m_rgb24Buffer, (unsigned int)width, (unsigned int)height, true);
        rgbBuffer = m_rgb24Buffer;
        sampleBits = 8;
        pixelSamples = 3;
        hasAlpha = NO;
        isPlanar = NO;
        bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaNone;
    }
    else if(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange == pixelFormat || kCVPixelFormatType_420YpCbCr8BiPlanarFullRange == pixelFormat)
    {
        if(width * height * 3 > m_rgb24BufferSize)
        {
            if(m_rgb24Buffer)
            {
                delete[] m_rgb24Buffer;
            }
            m_rgb24BufferSize = width * height * 3;
            m_rgb24Buffer = new unsigned char[m_rgb24BufferSize];
        }
        convert_y420nv_to_rgb24_buffer((unsigned char *)data[0], (unsigned char *)data[1], m_rgb24Buffer, (unsigned int)width, (unsigned int)height, false);
        rgbBuffer = m_rgb24Buffer;
        sampleBits = 8;
        pixelSamples = 3;
        hasAlpha = NO;
        isPlanar = NO;
        bitmapInfo = kCGBitmapByteOrderDefault | kCGImageAlphaNone;
    }
    else if(kCVPixelFormatType_32BGRA == pixelFormat)
    {
        rgbBuffer = data[0];
        sampleBits = 8;
        pixelSamples = 4;
        hasAlpha = YES;
        isPlanar = NO;
        bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
    }
    else if(kCVPixelFormatType_32ARGB == pixelFormat)
    {
        rgbBuffer = data[0];
        sampleBits = 8;
        pixelSamples = 4;
        hasAlpha = YES;
        isPlanar = NO;
        bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedFirst;
    }
    
    int pixelBits = pixelSamples * sampleBits;
    int rowBytes = (width * pixelBits + 31) / 32 * 4;
    NSImageRep *imageRep = NULL;
    if(kCVPixelFormatType_32BGRA == pixelFormat || kCVPixelFormatType_32ARGB == pixelFormat)
    {
        // Create a device-dependent RGB color space
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB(); 
        // Create a bitmap graphics context with the sample buffer data
        CGContextRef context = CGBitmapContextCreate(rgbBuffer, width, height, sampleBits, rowBytes, colorSpace, bitmapInfo); 
        // Create a Quartz image from the pixel data in the bitmap graphics context
        CGImageRef quartzImage = CGBitmapContextCreateImage(context);
        // Free up the context and color space
        CGContextRelease(context); 
        CGColorSpaceRelease(colorSpace);
        // Create an image object from the Quartz image
        imageRep = [[NSBitmapImageRep alloc] initWithCGImage:quartzImage];
        // Release the Quartz image
        CGImageRelease(quartzImage);
    }
    else
    {
        imageRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&rgbBuffer 
                                                           pixelsWide:width 
                                                           pixelsHigh:height 
                                                        bitsPerSample:sampleBits 
                                                      samplesPerPixel:pixelSamples 
                                                             hasAlpha:hasAlpha 
                                                             isPlanar:isPlanar 
                                                       colorSpaceName:NSDeviceRGBColorSpace 
                                                          bytesPerRow:rowBytes
                                                         bitsPerPixel:pixelBits];
    }
    if(imageRep)
    {
        if([m_lock tryLock])
        {
            [m_imageRep release];
            m_imageRep = [imageRep retain];
            m_imageWidth = width;
            m_imageHeight = height;
            [m_lock unlock];
        }
        [imageRep release];
    }
    
    [self performSelectorOnMainThread:@selector(reDisplayinMainThread) withObject:self waitUntilDone:NO];
    
    return 0;
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Drawing code here.
    NSRect bounds = [self bounds];
//	[[NSColor clearColor] set];
    [[NSColor grayColor] set];
    NSRectFill(bounds);
    
    if([m_lock tryLock])
    {
        if(NULL != m_imageRep)
        {				
            NSRect drawRect = bounds;
            drawRect.origin = NSZeroPoint;
            float viewWidth = drawRect.size.width, viewHeight = drawRect.size.height;
            float viewRatio = viewWidth / (float)viewHeight;
            float frameRatio = m_imageWidth / (float)m_imageHeight;
            if(viewRatio != frameRatio)
            {
                if(viewRatio > frameRatio)
                {
                    drawRect.size.width = (int)(viewHeight * frameRatio);
                    drawRect.origin.x = (int)((viewWidth - drawRect.size.width + 1) / 2);
                }
                else
                {
                    drawRect.size.height = (int)(viewWidth / frameRatio);
                    drawRect.origin.y = (int)((viewHeight - drawRect.size.height + 1) / 2);
                }
            }
            [m_imageRep drawInRect:drawRect];
        }
        [m_lock unlock];
    }
}

- (void)reDisplayinMainThread
{
	[self setNeedsDisplay:YES];
}

@end

#endif
