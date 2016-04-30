//
//  OpenGLView.m
//  Interconnect
//
//  Created by oroboto on 10/04/2016.
//  Copyright © 2016 oroboto. All rights reserved.
//

#import "OpenGLView.h"
#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#import <time.h>
#import "HostStore.h"
#import "Node.h"
#import "Host.h"
#import "NSFont_OpenGL.h"
#import "glm/vec3.hpp"
#import "glm/gtc/matrix_transform.hpp"

#define kPiOn180 0.0174532925f
#define kEnableVerticalSync NO
#define kEnablePerspective YES
#define kEnableFPSLog NO
#define kNodeRadiusGrowthPerSecond 0.7
#define kNodeVolumeGrowthPerSecond 0.01
#define kDisplayListCountForText 95
#define kCameraInitialX 0
#define kCameraInitialZ 8

@interface OpenGLView()

@property (nonatomic) CVDisplayLinkRef displayLink;     // display link for managing rendering thread
@property (nonatomic) int64_t lastTicks;
@property (nonatomic) BOOL isLightOn;
@property (nonatomic) BOOL isWorldRotating;

@property (nonatomic) GLfloat rotateY;                  // rotation around Y-axis (looking left and right: our heading)
@property (nonatomic) GLfloat rotateX;                  // rotation around X-axis
@property (nonatomic) GLfloat translateX;               // translation on X-axis (movement through space)
@property (nonatomic) GLfloat translateZ;               // translation on Z-axis (movement through space)
@property (nonatomic) GLfloat worldRotateY;
@property (nonatomic) GLfloat worldRotateX;
@property (nonatomic) NSPoint trackingMousePosition;
@property (nonatomic) BOOL picking;
@property (nonatomic) Host* previousSelection;
@property (nonatomic) NSUInteger lastNodeCount;
@property (nonatomic) double fps;

@property (nonatomic) GLuint displayListNode;           // display list for node objects
@property (nonatomic) GLuint displayListFontBase;       // base pointer to display lists for font set
@property (nonatomic) GLUquadricObj* quadric;

@end

@implementation OpenGLView

#pragma mark - Initialisation

- (void)awakeFromNib
{
    NSLog(@"awakeFromNib");

    _lastTicks = 0;
    _isLightOn = NO;
    _isWorldRotating = NO;
    
    // "Camera" movement is done by rotating and translating modelview in opposite angle / direction
    _rotateY = 0;
    _rotateX = 0;
    _translateX = kCameraInitialX;
    _translateZ = kCameraInitialZ;
    
    // "World" movement (spin world around origin)
    _worldRotateX = 0;
    _worldRotateY = 0;
    
    _picking = NO;
    
    [self becomeFirstResponder];
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)prepareOpenGL
{
    NSLog(@"prepareOpenGL");
    
    _quadric = gluNewQuadric();
    gluQuadricNormals(_quadric, GLU_SMOOTH);
    
    [self buildFontDisplayList];
    [self buildNodeDisplayList];
    
    glShadeModel(GL_SMOOTH);
    glClearColor(0, 0, 0, 0);

    //
    // Depth Buffer
    //  Like layers into the screen, keeps track of how deep objects are into the screen.
    //
    glClearDepth(1.0f);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);

    glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_NICEST);
    
    // Ambient light
    GLfloat lightAmbient[]  = {0.5f, 0.5f, 0.5f, 1.0f};
    GLfloat lightDiffuse[]  = {1.0f, 1.0f, 1.0f, 1.0f};
    GLfloat lightPosition[] = {0.0f, 0.0f, 2.0f, 1.0f};     // toward the viewer, in front of objects
    glLightfv(GL_LIGHT1, GL_AMBIENT, lightAmbient);
    glLightfv(GL_LIGHT1, GL_DIFFUSE, lightDiffuse);
    glLightfv(GL_LIGHT1, GL_POSITION, lightPosition);
    glEnable(GL_LIGHT1);
    
    // Only swap double buffers during vertical retrace (synchronisation with screen refresh rate)
    if (kEnableVerticalSync)
    {
        GLint swapInterval = 1;
        [[self openGLContext] setValues:&swapInterval forParameter:NSOpenGLCPSwapInterval];
    }

    // Create a Core Video display link capable of being used with all active displays
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    
    // Set the renderer output callback
    CVDisplayLinkSetOutputCallback(_displayLink, &displayLinkCallback, (__bridge void * _Nullable)(self));
    
    // Set the display link for the current renderer
    CGLContextObj cglContext = [[self openGLContext] CGLContextObj];
    CGLPixelFormatObj cglPixelFormat = [[self pixelFormat] CGLPixelFormatObj];
    CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink, cglContext, cglPixelFormat);
    
    // Activate the display link
    CVDisplayLinkStart(_displayLink);
}

- (void)dealloc
{
    // Release the display link
    CVDisplayLinkRelease(_displayLink);
    
    glDeleteLists(_displayListFontBase, kDisplayListCountForText);
    glDeleteLists(_displayListNode, 1);
    gluDeleteQuadric(_quadric);
}

#pragma mark - Text

- (void)buildFontDisplayList
{
    NSFont *font;
    
    _displayListFontBase = glGenLists(kDisplayListCountForText);   // storage for 95 textures (one per character)
    font = [NSFont fontWithName:@"Courier-Bold" size:10];

    if ( ! [font makeGLDisplayListsWithFirstCharacter:' ' count:kDisplayListCountForText displayListBase:_displayListFontBase])
    {
        NSLog(@"Could not create font display list");
    }
}

- (void) glPrint:(NSString *)fmt, ...
{
    NSString* text;
    va_list ap;
    unichar* uniBuffer;
    
    if (fmt == nil || [ fmt length ] == 0)
    {
        return;
    }
    
    va_start(ap, fmt);
    text = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    
    glPushAttrib(GL_LIST_BIT);                  // push display list bits
    
    // Rebase the base list pointer so that we can use ASCII character codes to index and find
    // the right display list to draw. 32 == space, the character in our first display list.
    glListBase(_displayListFontBase - 32);
    uniBuffer = static_cast<unichar*>(calloc([text length], sizeof(unichar)));
    [text getCharacters:uniBuffer];

    // Draw n display lists, the index of each being stored in a word of uniBuffer (the string)
    glCallLists([text length], GL_UNSIGNED_SHORT, uniBuffer);
    free(uniBuffer);

    glPopAttrib();                              // pop display list bits
}


#pragma mark - Responder Chain

- (void)keyDown:(NSEvent *)theEvent
{
    if ([[theEvent characters] isEqualToString:@"l"])
    {
        _isLightOn = ! _isLightOn;
    }
    else if ([[theEvent characters] isEqualToString:@"w"])
    {
        _isWorldRotating = ! _isWorldRotating;
    }
    else if ([theEvent modifierFlags] & NSNumericPadKeyMask)
    {
        [self interpretKeyEvents:[NSArray arrayWithObject:theEvent]];
    }
    else
    {
        [super keyDown:theEvent];
    }
}

- (IBAction)moveUp:(id)sender
{
    //
    // Move forwards along the X and Z planes based on our heading
    //
    //  Z plane gets more negative into the screen, X more negative to the left
    //
    _translateX -= (GLfloat)sin(_rotateY * kPiOn180) * 0.5f;
    _translateZ -= (GLfloat)cos(_rotateY * kPiOn180) * 0.5f;

    NSLog(@"x: %.2f, z: %.2f", _translateX, _translateZ);
}

- (IBAction)moveDown:(id)sender
{
    //
    // Move backwards along the X and Z planes based on our heading
    //
    //  Z plane gets more negative into the screen, X more negative to the left
    //
    _translateX += (GLfloat)sin(_rotateY * kPiOn180) * 0.5f;
    _translateZ += (GLfloat)cos(_rotateY * kPiOn180) * 0.5f;
    
    NSLog(@"x: %.2f, z: %.2f", _translateX, _translateZ);
}

- (IBAction)moveLeft:(id)sender
{
    if (_isWorldRotating)
    {
        _worldRotateY += 0.5f;
    }
    else
    {
        // Rotate heading / view counter-clockwise (left)
        _rotateY += 0.5f;   // CCW in degrees
    }
}

- (IBAction)moveRight:(id)sender
{
    if (_isWorldRotating)
    {
        _worldRotateY -= 0.5f;
    }
    else
    {
        // Rotate heading / view counter-clockwise (right)
        _rotateY -= 0.5f;   // CW in degrees
    }
}

- (void)mouseDown:(NSEvent *)theEvent
{
    _trackingMousePosition = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    _picking = YES;
}

- (void)mouseUp:(NSEvent*)theEvent
{
    _picking = NO;
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    NSPoint locationInView = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    
    // Cocoa View puts (0,0) at bottom-left corner of screen
    CGFloat deltaX = locationInView.x - _trackingMousePosition.x;
    CGFloat deltaY = locationInView.y - _trackingMousePosition.y;

    if (_isWorldRotating)
    {
        _worldRotateY -= (deltaX * 0.1f);
        _worldRotateX -= (deltaY * 0.1f);
    }
    else
    {
        _rotateY -= (deltaX * 0.1f);
        _rotateX -= (deltaY * 0.1f);
    }
    
    _trackingMousePosition = locationInView;
}

#pragma mark - View

/**
 * Deal with window resizing and properly reset the perspective.
 */
- (void)reshape
{
    NSRect rect = [self bounds];        // view's size and position in its own co-ordinate system
    
    NSLog(@"reshape to %.2fx%.2f", rect.size.width, rect.size.height);
    
    // Set up a perspective view (things in distance get smaller)
    glViewport(0, 0, rect.size.width, rect.size.height);
    
    if (kEnablePerspective)
    {
        // Projection Matrix responsible for adding perspective to scene.
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();                   // reset matrix to original / default state
        
        //
        // 45 degree fovy, fovx is based on aspect ratio of screen. Can't see anything closer than zNear or further than zFar
        //
        gluPerspective(45.0f, (GLfloat)rect.size.width/(GLfloat)rect.size.height, 0.1f, 100.0f);
        
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
    }
}

static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                    const CVTimeStamp* now,
                                    const CVTimeStamp* outputTime,
                                    CVOptionFlags flagsIn,
                                    CVOptionFlags* flagsOut,
                                    void* displayLinkContext)
{
    /**
     * This method is called on the high priority display link thread and must synchronise access to the data store
     */
    return [(__bridge OpenGLView*)displayLinkContext getFrameForTime:outputTime actualTime:now];
}

/**
 * outputTime specifies the timestamp when the frame *will* be output to the screen
 */
- (CVReturn)getFrameForTime:(const CVTimeStamp*)outputTime actualTime:(const CVTimeStamp*)actualTime
{
    double nominalRefreshRate = outputTime->videoTimeScale / outputTime->videoRefreshPeriod;    // fps
    double elapsed_seconds = (actualTime->hostTime - _lastTicks) / CVGetHostClockFrequency();   // should we use outputTime->hostTime?

    _fps = 1 / elapsed_seconds;

    if (kEnableFPSLog)
    {
        NSLog(@"getFrameForTime (nominal refresh rate: %.2f FPS, actual FPS: %.2f)", nominalRefreshRate, _fps);
    }
    
    // The rendering context connects OpenGL to Cocoa's view and stores all OpenGL state
    [[self openGLContext] makeCurrentContext];
    
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();                                       // reset ModelView matrix, screen center now 0.0f, 0.0f, 0.0f
    glClearColor(0, 0, 0, 0);

    if (_isLightOn)
    {
        glEnable(GL_LIGHTING);
    }
    else
    {
        glDisable(GL_LIGHTING);
    }

    if (elapsed_seconds > 1)
    {
        elapsed_seconds = 1;
    }
    else if (elapsed_seconds < 0.01)    // ~100fps
    {
        elapsed_seconds = 0.01;
    }

    [self drawNodeSphere:elapsed_seconds];
    [self drawHUD];
    
    [[self openGLContext] flushBuffer];
    
    _lastTicks = actualTime->hostTime;      // should we use outputTime->hostTime?

    return kCVReturnSuccess;
}

#pragma mark - Drawing

- (void)translateForCamera
{
    glLoadIdentity();
    GLfloat sceneRotateY = 360.0f - _rotateY;
    GLfloat sceneRotateX = 360.0f - _rotateX;
    GLfloat sceneTranslateX = -_translateX;
    GLfloat sceneTranslateZ = -_translateZ;
    
    glRotatef(sceneRotateY, 0.0f, 1.0f, 0.0);       // rotation around Y-axis (looking left and right)
    glRotatef(sceneRotateX, 1.0f, 0.0f, 0.0);       // rotation around Y-axis (looking left and right)
    glTranslatef(sceneTranslateX, 0.0f, sceneTranslateZ);
    
//  NSLog(@"x: %.2f z: %.2f", sceneTranslateX, sceneTranslateZ);
}

- (void)drawNodeSphere:(double)secondsSinceLastFrame
{
    glClearColor(0,0,0,0);
    
    //
    // Simulate movement of the camera by rotating and translating the model view in the opposite way to the "camera" (our PoV)
    //
    // NOTE: The visual effect of moving the camera (which is like being fixed in one position and moving your head around to
    //       look around) is very different from moving the objects in the world (ie. spinning them around the origin but
    //       perhaps still allowing the X,Y,Z position of the camera to be set.
    //
    // TODO: Toggle between moving the camera and rotating the objects themselves.
    //
    
    // This translates the origin (0, 0, 0) to a new origin
    [self translateForCamera];
    
    glColor3f(0, 1, 0);
    glRasterPos2f(0.06, 0.06);
    [self glPrint:@"localhost"];
    
    [self drawNode:nil x:0 y:0 z:0 secondsSinceLastFrame:secondsSinceLastFrame];     // origin marker
    HostStore *hostStore = [HostStore sharedStore];
    [hostStore lockStore];
    NSDictionary* orbitals = [hostStore inhabitedOrbitals];
    NSUInteger orbitalCount = [[orbitals allKeys] count];
    
    _previousSelection = nil;
    _lastNodeCount = 0;

    for (NSNumber* orbitalNumber in orbitals)
    {
        NSArray* nodes = [orbitals objectForKey:orbitalNumber];
        NSUInteger nodeCount = [nodes count];
        float planeCount = floor(sqrt((double)nodeCount) + 1);
        float degreeSpacing = 360.0f / planeCount;

        _lastNodeCount += nodeCount;
        
//      NSLog(@"Orbital %d with %lu nodes generates plane count of %.2f and degree spacing %.2f", [orbitalNumber intValue], (unsigned long)nodeCount, planeCount, degreeSpacing);
        
        NSUInteger nodesDrawn = 0;
        float thetaOffset = [orbitalNumber intValue] * 30.0;
        for (float theta = thetaOffset; theta < (thetaOffset + 360.0f); theta += degreeSpacing)
        {
            for (float phi = 10; phi < 370.0; phi += degreeSpacing)
            {
                if (nodesDrawn < nodeCount)
                {
                    Node* node = [nodes objectAtIndex:nodesDrawn];
                    
                    float radius = node.radius;

                    GLfloat x = radius * sin(phi * (2*M_PI / 360.0)) * cos(theta * (2*M_PI / 360.0));
                    GLfloat y = radius * sin(phi * (2*M_PI / 360.0)) * sin(theta * (2*M_PI / 360.0));
                    GLfloat z = radius * cos(phi * (2*M_PI / 360.0));

                    glColor3f((1.0 / orbitalCount) * [orbitalNumber floatValue], 0, 0);

                    [self drawNode:node x:x y:y z:z secondsSinceLastFrame:secondsSinceLastFrame];
                    
                    if (node.radius < [orbitalNumber floatValue])
                    {
                        // The node needs to float to its true orbital position
                        [node growRadius:kNodeRadiusGrowthPerSecond*secondsSinceLastFrame];
                    }
                    else if (node.radius > [orbitalNumber floatValue])
                    {
                        // The node needs to float to its true orbital position
                        [node shrinkRadius:kNodeRadiusGrowthPerSecond*secondsSinceLastFrame];
                    }

                    if (node.volume < [node targetVolume])
                    {
                        [node growVolume:kNodeVolumeGrowthPerSecond*secondsSinceLastFrame];
                    }
                    else if (node.volume > [node targetVolume])
                    {
                        [node shrinkVolume:kNodeVolumeGrowthPerSecond*secondsSinceLastFrame];
                    }
                    
                    nodesDrawn++;
                }
            }
        }
        assert(nodesDrawn == nodeCount);
    }
    
    [hostStore unlockStore];
 
}

- (void)drawNode:(Node*)node x:(GLfloat)x y:(GLfloat)y z:(GLfloat)z secondsSinceLastFrame:(double)secondsSinceLastFrame
{
    GLfloat s = 0.05;
    
    if (node)
    {
        s = node.volume;
    }
    
    // Push the world translation matrix so that each time we draw a quad it's translated from the translated world origin,
    // not the translation of the last quad drawn (otherwise we end up drawing a torus).
    glPushMatrix();
    
    GLfloat worldRotateY = 360.0f - _worldRotateY;
    GLfloat worldRotateX = 360.0f - _worldRotateX;
    
    glRotatef(worldRotateY, 0.0f, 1.0f, 0.0);       // rotation around Y-axis (looking left and right)
    glRotatef(worldRotateX, 1.0f, 0.0f, 0.0);       // rotation around Y-axis (looking left and right)

    if (_picking)
    {
        GLint viewport[4];
        GLdouble modelViewMatrix[16], projectionMatrix[16];
        GLdouble rayVertexNear[3];
        GLdouble rayVertexFar[3];
        
        glGetDoublev(GL_MODELVIEW_MATRIX, modelViewMatrix);
        glGetDoublev(GL_PROJECTION_MATRIX, projectionMatrix);
        glGetIntegerv(GL_VIEWPORT, viewport);
        
        // Get the ray entry and exit points on the projection frustum
        gluUnProject(_trackingMousePosition.x, _trackingMousePosition.y, 0.0, modelViewMatrix, projectionMatrix, viewport, &rayVertexNear[0], &rayVertexNear[1], &rayVertexNear[2]);
        gluUnProject(_trackingMousePosition.x, _trackingMousePosition.y, 1.0, modelViewMatrix, projectionMatrix, viewport, &rayVertexFar[0], &rayVertexFar[1], &rayVertexFar[2]);

        glm::vec3 rayVectorNear, rayVectorFar, sphereCenter;
        rayVectorNear.x = rayVertexNear[0];
        rayVectorNear.y = rayVertexNear[1];
        rayVectorNear.z = rayVertexNear[2];
        rayVectorFar.x = rayVertexFar[0];
        rayVectorFar.y = rayVertexFar[1];
        rayVectorFar.z = rayVertexFar[2];
        sphereCenter.x = x;
        sphereCenter.y = y;
        sphereCenter.z = z;
        
        // Ray / sphere intersection test
        glm::vec3 vectDirToSphere = sphereCenter - rayVectorNear;
        glm::vec3 vectRayDir = glm::normalize(rayVectorNear - rayVectorFar);
        float lineLength = glm::distance(rayVectorNear, rayVectorFar);
        float t = glm::dot(vectDirToSphere, vectRayDir);
        glm::vec3 closestPoint = rayVectorNear + (vectRayDir*t);
        
        if (glm::distance(sphereCenter, closestPoint) <= s)
        {
            node.selected = YES;
        }
        else
        {
            node.selected = NO;
        }
    }

    if (node && node.selected)
    {
        Host* host = (Host*)node;
        glColor3f(1, 1, 0);
        glRasterPos3f(x+s, y+s, z);
        [self glPrint:[NSString stringWithFormat:@"%@ [in: %lu] [out: %lu]", host.hostname.length ? host.hostname : host.ipAddress, host.bytesReceived, host.bytesSent]];
        
        if (_previousSelection != nil)
        {
            // This is simply debugging used to detect multiple selection (ie. ray passed through > 1 node)
            NSLog(@"Selected %@ (%.2f, %.2f, %.2f) but %@ already selected", node.identifier, x, y, z, _previousSelection.identifier);
        }
        
        _previousSelection = node;
    }
    
    glTranslatef(x, y, z);

    // Scale the node (nominally at size 1,1,1) to the size we need
    glScalef(s, s, s);

    glCallList(_displayListNode);

    glPopMatrix();
}

- (void)buildNodeDisplayList
{
    GLfloat radius = 1.00;
    
    _displayListNode = glGenLists(1);
    
    glNewList(_displayListNode, GL_COMPILE);
    
    gluSphere(_quadric, radius, 32, 32);
    
    glEndList();
}

- (void)drawHUD
{
    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);

    glMatrixMode(GL_PROJECTION);
    glPushMatrix();
    glLoadIdentity();
    
    // left, right, bottom, top, z
    glOrtho(0, viewport[2], viewport[3], 0, -1.0, 1.0);

    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();
    glColor3f(1, 1, 1);
    glRasterPos3f(5, 15, 0);
    [self glPrint:[NSString stringWithFormat:@"%lu hosts [%.2f FPS, control: %@]", _lastNodeCount, _fps, _isWorldRotating ? @"world" : @"camera"]];
    glPopMatrix();

    glMatrixMode(GL_PROJECTION);
    glPopMatrix();

    glMatrixMode(GL_MODELVIEW);
}

@end
