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
#import "NodeStore.h"
#import "Node.h"

//#define kPiOn180 M_PI / 180.0
#define kPiOn180 0.0174532925f
#define kEnableVerticalSync NO
#define kEnablePerspective YES
#define kEnableFPSLog NO
#define kNodeRotationDegreesPerSecond   50
#define kNodeRadiusGrowthPerSecond 0.4

@interface OpenGLView()

@property (nonatomic) CVDisplayLinkRef displayLink;     // display link for managing rendering thread
@property (nonatomic) int64_t lastTicks;
@property (nonatomic) float rotationAngle;
@property (nonatomic) BOOL isLightOn;

@property (nonatomic) GLfloat rotateY;                  // rotation around Y-axis (looking left and right: our heading)
@property (nonatomic) GLfloat rotateX;                  // rotation around X-axis
@property (nonatomic) GLfloat translateX;               // translation on X-axis (movement through space)
@property (nonatomic) GLfloat translateZ;               // translation on Z-axis (movement through space)
@property (nonatomic) NSPoint trackingMousePosition;

@end

@implementation OpenGLView

#pragma mark - Initialisation

- (void)awakeFromNib
{
    NSLog(@"awakeFromNib");
    
    _lastTicks = 0;
    _rotationAngle = 0.0f;
    _isLightOn = NO;
    
    // "Camera" movement is done by rotating and translating modelview in opposite angle / direction
    _rotateY = 0;
    _rotateX = 0;
    _translateX = 0;
    _translateZ = 0;
    
    [self becomeFirstResponder];
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)prepareOpenGL
{
    NSLog(@"prepareOpenGL");
    
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
    NSLog(@"dealloc");
    
    // Release the display link
    CVDisplayLinkRelease(_displayLink);
}

#pragma mark - Responder Chain

- (void)keyDown:(NSEvent *)theEvent
{
    NSLog(@"key: %@", [theEvent characters]);
    
    if ([[theEvent characters] isEqualToString:@"l"])
    {
        _isLightOn = ! _isLightOn;
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
    //
    // Rotate heading / view counter-clockwise (left)
    //
    _rotateY += 0.5f;   // CCW in degrees
}

- (IBAction)moveRight:(id)sender
{
    //
    // Rotate heading / view counter-clockwise (right)
    //
    _rotateY -= 0.5f;   // CW in degrees
}

- (void)mouseDown:(NSEvent *)theEvent
{
//  NSLog(@"mouseDown");
    
    _trackingMousePosition = [self convertPoint:[theEvent locationInWindow] fromView:nil];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    NSPoint locationInView = [self convertPoint:[theEvent locationInWindow] fromView:nil];
    
    //
    // Cocoa View puts (0,0) at bottom-left corner of screen
    //
//  NSLog(@"mouse %fx%f", locationInView.x, locationInView.y);
    
    CGFloat deltaX = locationInView.x - _trackingMousePosition.x;
    CGFloat deltaY = locationInView.y - _trackingMousePosition.y;
    
//  NSLog(@"deltaX %.2f, deltaY %.2f", deltaX, deltaY);

    _rotateY -= (deltaX * 0.1f);
    _rotateX -= (deltaY * 0.1f);
    
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
    CVReturn result = [(__bridge OpenGLView*)displayLinkContext getFrameForTime:outputTime actualTime:now];
    return result;
}

/**
 * outputTime specifies the timestamp when the frame *will* be output to the screen
 */
- (CVReturn)getFrameForTime:(const CVTimeStamp*)outputTime actualTime:(const CVTimeStamp*)actualTime
{
    double nominalRefreshRate = outputTime->videoTimeScale / outputTime->videoRefreshPeriod;    // fps
    double elapsed_seconds = (actualTime->hostTime - _lastTicks) / CVGetHostClockFrequency();   // should we use outputTime->hostTime?
    double fps = 1 / elapsed_seconds;

    if (kEnableFPSLog)
    {
        NSLog(@"getFrameForTime (nominal refresh rate: %.2f FPS, actual FPS: %.2f)", nominalRefreshRate, fps);
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

    [self drawNodeSphere:elapsed_seconds];
    
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
    
    NSLog(@"x: %.2f z: %.2f", sceneTranslateX, sceneTranslateZ);
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
    
    glColor3f(0, 0, 1);
    [self drawNode:nil x:0 y:0 z:0 secondsSinceLastFrame:secondsSinceLastFrame];     // origin marker

    NSDictionary* orbitals = [[NodeStore sharedStore] inhabitedOrbitals];
    NSUInteger orbitalCount = [[orbitals allKeys] count];

    for (NSNumber* orbitalNumber in orbitals)
    {
        NSArray* nodes = [orbitals objectForKey:orbitalNumber];
        NSUInteger nodeCount = [nodes count];
        float planeCount = floor(sqrt((double)nodeCount) + 1);
        float degreeSpacing = 360.0f / planeCount;
        
        NSLog(@"Orbital %d with %d nodes generates plane count of %.2f and degree spacing %.2f", [orbitalNumber intValue], nodeCount, planeCount, degreeSpacing);

        glColor3f((1.0 / orbitalCount) * [orbitalNumber floatValue], 0, 0);
        
        NSUInteger nodesDrawn = 0;
        for (float theta = 0; theta < 360.0f; theta += degreeSpacing)
        {
            for (float phi = 0; phi < 360.0f; phi += degreeSpacing)
            {
                if (nodesDrawn < nodeCount)
                {
                    Node* node = [nodes objectAtIndex:nodesDrawn];
                    
                    float radius = node.radius;

                    GLfloat x = radius * sin(phi * (2*M_PI / 360.0)) * cos(theta * (2*M_PI / 360.0));
                    GLfloat y = radius * sin(phi * (2*M_PI / 360.0)) * sin(theta * (2*M_PI / 360.0));
                    GLfloat z = radius * cos(phi * (2*M_PI / 360.0));
                    
                    [self drawNode:node x:x y:y z:z secondsSinceLastFrame:secondsSinceLastFrame];
                    
                    if (node.radius < [orbitalNumber floatValue])
                    {
                        // The node needs to float to its true orbital position
                        [node setRadius:(node.radius + (kNodeRadiusGrowthPerSecond*secondsSinceLastFrame))];
                    }
                    
                    nodesDrawn++;
                }
            }
        }
        assert(nodesDrawn == nodeCount);
    }
}

- (void)drawNode:(Node*)node x:(GLfloat)x y:(GLfloat)y z:(GLfloat)z secondsSinceLastFrame:(double)secondsSinceLastFrame
{
    GLfloat s = 0.05;
    GLfloat rotation = 0.0;
    
    if (node)
    {
        s = node.volume;
        rotation = node.rotation;
    }
    
    // Push the world translation matrix so that each time we draw a quad it's translated from the translated world origin,
    // not the translation of the last quad drawn (otherwise we end up drawing a torus).
    glPushMatrix();
    glTranslatef(x, y, z);

    // x, y, z represent the vector along which the rotation occurs, in our case, the y axis
    glRotatef(rotation, 0, 1, 0);

    glBegin(GL_QUADS);
    {
        glVertex3f(-s,  s, -s); //F T L
        glVertex3f( s,  s, -s); //F T R
        glVertex3f( s, -s, -s); //F B R
        glVertex3f(-s, -s, -s); //F B L
        
        glVertex3f(-s, -s, -s); //F B L
        glVertex3f( s, -s, -s); //F B R
        glVertex3f( s, -s,  s); //B B R
        glVertex3f(-s, -s,  s); //B B L
        
        glVertex3f(-s,  s,  s); //B T L
        glVertex3f( s,  s,  s); //B T R
        glVertex3f( s, -s,  s); //B B R
        glVertex3f(-s, -s,  s); //B B L
        
        glVertex3f(-s,  s,  s); //B T L
        glVertex3f(-s,  s, -s); //F T L
        glVertex3f(-s, -s, -s); //F B L
        glVertex3f(-s, -s,  s); //B B L
        
        glVertex3f(-s,  s,  s); //B T L
        glVertex3f( s,  s,  s); //B T R
        glVertex3f( s,  s, -s); //F T R
        glVertex3f(-s,  s, -s); //F T L
        
        glVertex3f( s,  s, -s); //F T R
        glVertex3f( s,  s,  s); //B T R
        glVertex3f( s, -s,  s); //B B R
        glVertex3f( s, -s, -s); //F B R
    }
    glEnd();

    if (node)
    {
        // In order to maintain smooth rotation the amount of angle to add grows and shrinks depending on the frame rate
        node.rotation += (kNodeRotationDegreesPerSecond * secondsSinceLastFrame);
    }

    glPopMatrix();
}

- (void)drawTriangleAndSquareWithRotation:(double)elapsed_seconds
{
    // In order to maintain smooth rotation the amount of angle to add grows and shrinks depending on the frame rate
    _rotationAngle += (50.5 * elapsed_seconds);

    glColor3f(0, 1, 0);
    
    // Translation accumulates, each translation is from last position
    glTranslatef(-1.5f, 0.0f, -6.0f);
    
    // x, y, z represent the vector along which the rotation occurs, in our case, the y axis
    glRotatef(_rotationAngle, 0, 1, 0);
    
    // All co-ordinates are relative to the translated position
    glBegin(GL_TRIANGLES);
    {
        glVertex3f( 0.0f, 1.0f, 0.0f);              // Top
        glColor3f(0, 0.3, 0);
        glVertex3f(-1.0f,-1.0f, 0.0f);              // Bottom Left
        glVertex3f( 1.0f,-1.0f, 0.0f);              // Bottom Right
    }
    glEnd();
    
    // NOTE: new identity load, must do this here because otherwise we'd be translating AFTER our rotation which would
    //       create a completely different (non lateral) translation. Note we also change the co-ordinates from the
    //       original drawTriangleAndSquare because now we're not translating from our previously translated point, we
    //       are translating from 0, 0, 0 again.
    glLoadIdentity();

    glTranslatef(1.5f,0.0f,-6.0f);
    glBegin(GL_QUADS);
    {
        glVertex3f(-1.0f, 1.0f, 0.0f);              // Top Left
        glVertex3f( 1.0f, 1.0f, 0.0f);              // Top Right
        glVertex3f( 1.0f,-1.0f, 0.0f);              // Bottom Right
        glVertex3f(-1.0f,-1.0f, 0.0f);              // Bottom Left
    }
    glEnd();
}

- (void)drawTriangleAndSquareWithRotation3D:(double)elapsed_seconds
{
    // In order to maintain smooth rotation the amount of angle to add grows and shrinks depending on the frame rate
    _rotationAngle += (50.5 * elapsed_seconds);      // 0.5 degrees per second
    
    // Translation accumulates, each translation is from last position
    glTranslatef(-1.5f, 0.0f, -6.0f);
    
    // x, y, z represent the vector along which the rotation occurs, in our case, the y axis
    glRotatef(_rotationAngle, 0, 1, 0);
    
    // All co-ordinates are relative to the translated position
    //
    // Create a pyramid. Top is +1 from its center, bottom is -1 from its center and -1 or +1 on x.
    //
    // Draw the triangle faces in counter-clockwise direction beginning with front face.
    //
    // Our pyramid does not need a bottom face because we only ever rotate it on its y axis (see ahove)
    glBegin(GL_TRIANGLES);
    {
        // Front face
        glColor3f(1.0f,0.0f,0.0f);          // Red
        glVertex3f( 0.0f, 1.0f, 0.0f);      // Top Of Triangle (Front)
        glColor3f(0.0f,1.0f,0.0f);          // Green
        glVertex3f(-1.0f,-1.0f, 1.0f);      // Left Of Triangle (Front) - counter clockwise
        glColor3f(0.0f,0.0f,1.0f);          // Blue
        glVertex3f( 1.0f,-1.0f, 1.0f);      // Right Of Triangle (Front) - counter clockwise
        
        // Right face
        glColor3f(1.0f,0.0f,0.0f);          // Red
        glVertex3f( 0.0f, 1.0f, 0.0f);      // Top Of Triangle (Right)
        glColor3f(0.0f,0.0f,1.0f);          // Blue
        glVertex3f( 1.0f,-1.0f, 1.0f);      // Left Of Triangle (Right)
        glColor3f(0.0f,1.0f,0.0f);          // Green
        glVertex3f( 1.0f,-1.0f, -1.0f);     // Right Of Triangle (Right)
        
        // Back face
        glColor3f(1.0f,0.0f,0.0f);          // Red
        glVertex3f( 0.0f, 1.0f, 0.0f);      // Top Of Triangle (Back)
        glColor3f(0.0f,1.0f,0.0f);          // Green
        glVertex3f( 1.0f,-1.0f, -1.0f);     // Left Of Triangle (Back)
        glColor3f(0.0f,0.0f,1.0f);          // Blue
        glVertex3f(-1.0f,-1.0f, -1.0f);     // Right Of Triangle (Back)
        
        // NOTE: We purposely leave off the left face so we can see into the pyramid
    }
    glEnd();        // closes path, creates polygon out of faces
    
    // NOTE: new identity load, must do this here because otherwise we'd be translating AFTER our rotation which would
    //       create a completely different (non lateral) translation. Note we also change the co-ordinates from the
    //       original drawTriangleAndSquare because now we're not translating from our previously translated point, we
    //       are translating from 0, 0, 0 again.
    glLoadIdentity();
    
    glTranslatef(1.5f,0.0f,-6.0f);
    glBegin(GL_QUADS);
    {
        glVertex3f(-1.0f, 1.0f, 0.0f);              // Top Left
        glVertex3f( 1.0f, 1.0f, 0.0f);              // Top Right
        glVertex3f( 1.0f,-1.0f, 0.0f);              // Bottom Right
        glVertex3f(-1.0f,-1.0f, 0.0f);              // Bottom Left
    }
    glEnd();
}

@end
