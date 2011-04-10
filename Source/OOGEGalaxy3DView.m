//
//  OOGEGalaxy3DView.m
//  GalaxyExtruder
//
//  Created by Jens Ayton on 2011-04-08.
//  Copyright 2011 the Oolite team. All rights reserved.
//

#import "OOGEGalaxy3DView.h"
#import <OpenGL/gl.h>
#import <OpenGL/glu.h>
#import "OOGEGalaxy.h"
#import <OoliteGraphics/OoliteGraphics.h>

@interface OOGEGalaxy3DView ()

- (id) finishInit;

- (void) galaxyChanged;

- (void) renderParticles;

-(void) makeTextureFromImage:(NSImage*)theImg forTexture:(GLuint*)texName;

@end


#define DRAW_AXES 1


#ifndef NDEBUG
static void CheckGLError(NSString *context);
#else
#define CheckGLError(context) do {} while (0)
#endif

#if DRAW_AXES
static void DrawAxes(BOOL inLabels, float inScale);
#else
#define DrawAxes(labels, scale) do {} while (0)
#endif


static void GetGLVersion(unsigned *major, unsigned *minor, unsigned *subminor);


@implementation OOGEGalaxy3DView

@synthesize drawForceVectors = _drawForceVectors;


- (id)initWithCoder:(NSCoder *)inCoder
{
	if ((self = [super initWithCoder:inCoder]))
	{
		self = [self finishInit];
	}
	return self;
}


- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame]))
	{
		self = [self finishInit];
    }
    return self;
}


- (id) finishInit
{
	[[self openGLContext] makeCurrentContext];
	
	unsigned major, minor, subminor;
	GetGLVersion(&major, &minor, &subminor);
	if (major == 1 && minor < 5)
	{
		OOLog(@"opengl.version", @"OpenGL 1.5 required.");
		return nil;
	}
	
	glEnable(GL_MULTISAMPLE_ARB);
	glClearColor(0, 0, 0, 1);
	glPointSize(32);
	glEnable(GL_POINT_SMOOTH);
	CheckGLError(@"after initial setup");
	
	_xrot = 30;
	_yrot = -45;
	
	NSImage *texture = [NSImage imageNamed:@"oolite-star-1"];
	[self makeTextureFromImage:texture forTexture:&_texName];
	CheckGLError(@"after loading point sprite texture");
	
	return self;
}


- (void)drawRect:(NSRect)rect
{
	[[self openGLContext] makeCurrentContext];
	
	// Set up camera
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();
	glTranslatef(0.0f, 0.0f, -100.0f);
	
	glRotatef(_xrot, 1.0f, 0.0f, 0.0f);
	glRotatef(_yrot, 0.0f, 1.0f, 0.0f);
	glScalef(1.0, -1.0, 1.0);
	CheckGLError(@"setting up model view matrix");
	
	// Draw
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	CheckGLError(@"clearing buffers");
	
	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE);
	
	[self renderParticles];
	
	CheckGLError(@"rendering particles");
	
#if DRAW_AXES
	DrawAxes(YES, 5.0f);
	CheckGLError(@"drawing axes");
#endif
	
	[[self openGLContext] flushBuffer];
	CheckGLError(@"flushing view");
}


- (void)reshape
{
	[[self openGLContext] makeCurrentContext];
	
	NSSize dimensions = self.frame.size;
	
	glViewport(0, 0, (GLsizei)dimensions.width, (GLsizei)dimensions.height);
	
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
	gluPerspective(45.0, dimensions.width / dimensions.height, 0.1, 300.0);
}


- (BOOL) isOpaque
{
	return YES;
}


- (OOGEGalaxy *) galaxy
{
	return _galaxy;
}


- (void) setGalaxy:(OOGEGalaxy *)galaxy
{
	if (galaxy != _galaxy)
	{
		if (galaxy != nil)
		{
			[[NSNotificationCenter defaultCenter] removeObserver:self name:kOOGEGalaxyChangedNotification object:_galaxy];
		}
		
		_galaxy = galaxy;
		[self galaxyChanged];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(galaxyChanged) name:kOOGEGalaxyChangedNotification object:galaxy];
	}
}


- (void) galaxyChanged
{
	[self setNeedsDisplay:YES];
	
	[[self openGLContext] makeCurrentContext];
	
	_starVBOUpToDate = NO;
}


- (void) updateStarVBOs
{
	if (_starVBO == 0)
	{
		OOGL(glGenBuffers(1, &_starVBO));
		OOGL(glGenBuffers(1, &_starColorVBO));
	}
	
	NSArray *systems = self.galaxy.systems;
	size_t size = sizeof(*_starVBOData) * 3 * systems.count;
	BOOL updateColor = NO;
	
	if (_starVBOSize != size)
	{
		_starVBOData = NSAllocateCollectable(size, 0);
		_starColorVBOData = NSAllocateCollectable(size, 0);
		if (_starVBOData == NULL || _starColorVBOData == NULL)  abort();
		_starVBOSize = size;
		updateColor = YES;
	}
	
	GLfloat *next = _starVBOData;
	for (OOGESystem *system in systems)
	{
		Vector p = system.position;
		*next++ = p.x;
		*next++ = p.y;
		*next++ = p.z;
	}
	
	OOGL(glBindBuffer(GL_ARRAY_BUFFER_ARB, _starVBO));
	OOGL(glBufferData(GL_ARRAY_BUFFER_ARB, size, _starVBOData, GL_DYNAMIC_DRAW_ARB));
	
	if (updateColor)
	{
		next = _starColorVBOData;
		for (OOGESystem *system in systems)
		{
			// Only RGB components, A is assumed to be 1.
			GLfloat color[4];
			[system getColorComponents:color];
			*next++ = color[0];
			*next++ = color[1];
			*next++ = color[2];
		}
		
		OOGL(glBindBuffer(GL_ARRAY_BUFFER_ARB, _starColorVBO));
		OOGL(glBufferData(GL_ARRAY_BUFFER_ARB, size, _starColorVBOData, GL_STATIC_DRAW_ARB));
	}
	
	_starVBOUpToDate = YES;
}


- (void) updateOriginalStarVBO
{
	if (_originalStarVBO == 0)
	{
		OOGL(glGenBuffers(1, &_originalStarVBO));
	}
	
	NSArray *systems = self.galaxy.systems;
	size_t size = sizeof(*_originalStarVBOData) * 3 * systems.count;
	
	if (_originalStarVBOSize != size)
	{
		_originalStarVBOData = NSAllocateCollectable(size, 0);
		if (_originalStarVBOData == NULL)  abort();
		_originalStarVBOSize = size;
	}
	
	GLfloat *next = _originalStarVBOData;
	for (OOGESystem *system in systems)
	{
		Vector p = system.originalPosition;
		*next++ = p.x;
		*next++ = p.y;
		*next++ = p.z;
	}
	
	OOGL(glBindBuffer(GL_ARRAY_BUFFER_ARB, _originalStarVBO));
	OOGL(glBufferData(GL_ARRAY_BUFFER_ARB, size, _originalStarVBOData, GL_STATIC_DRAW_ARB));
	
	_starVBOUpToDate = YES;
}


- (void) updateRouteVBO
{
	if (_routesVBO == 0)
	{
		OOGL(glGenBuffers(1, &_routesVBO));
	}
	
	NSArray *systems = self.galaxy.systems;
	NSUInteger count = 0;
	
	// Count neighbour pairs.
	for (OOGESystem *system in systems)
	{
		for (OOGESystem *neighbour in system.neighbours)
		{
			if (system.index < neighbour.index)
			{
				count++;
			}
		}
	}
	
	if (count == 0)  return;
	
	_routesCount = count * 2;
	
	// Allocate buffer.
	size_t size = sizeof(*_routesVBOData) * 2 * count;
	if (_routesVBOSize != size)
	{
		_routesVBOData = NSAllocateCollectable(size, 0);
		if (_routesVBOData == NULL)  abort();
		_routesVBOSize = size;
	}
	
	// Pack indices.
	GLushort *next = _routesVBOData;
	for (OOGESystem *system in systems)
	{
		GLushort sidx = system.index;
		for (OOGESystem *neighbour in system.neighbours)
		{
			GLushort nidx = neighbour.index;
			if (sidx < nidx)
			{
				*next++ = sidx;
				*next++ = nidx;
			}
		}
	}
	
	OOGL(glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _routesVBO));
	OOGL(glBufferData(GL_ELEMENT_ARRAY_BUFFER, size, _routesVBOData, GL_STATIC_DRAW_ARB));
	
	_routesVBOUpToDate = YES;
}


- (void) renderParticles
{
	NSArray *systems = self.galaxy.systems;
	NSUInteger count = systems.count;
	if (count == 0)  return;
	
	if (!_starVBOUpToDate)  [self updateStarVBOs];
	if (!_originalStarVBOUpToDate)  [self updateOriginalStarVBO];
	if (!_routesVBOUpToDate)  [self updateRouteVBO];
	
	OOGL(glEnableClientState(GL_VERTEX_ARRAY));
	OOGL(glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _routesVBO));
	
	// Draw original grid.
	OOGL(glColor3f(0.1, 0.2, 0.2));
	OOGL(glBindBuffer(GL_ARRAY_BUFFER, _originalStarVBO));
	OOGL(glVertexPointer(3, GL_FLOAT, 0, 0));
	OOGL(glDrawElements(GL_LINES, _routesCount, GL_UNSIGNED_SHORT, 0));
	
	// Draw current grid.
	OOGL(glColor3f(0.333, 0.333, 0.333));
	OOGL(glBindBuffer(GL_ARRAY_BUFFER, _starVBO));
	OOGL(glVertexPointer(3, GL_FLOAT, 0, 0));
	OOGL(glDrawElements(GL_LINES, _routesCount, GL_UNSIGNED_SHORT, 0));
	
	OOGL(glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0));
	
	// Draw stars.
	OOGL(glEnable(GL_TEXTURE_2D));
	OOGL(glBindTexture(GL_TEXTURE_2D, _texName));
	OOGL(glEnable(GL_POINT_SPRITE));
	OOGL(glTexEnvi(GL_POINT_SPRITE, GL_COORD_REPLACE, GL_TRUE));
	
	OOGL(glEnableClientState(GL_COLOR_ARRAY));
	OOGL(glBindBuffer(GL_ARRAY_BUFFER, _starColorVBO));
	OOGL(glColorPointer(3, GL_FLOAT, 0, 0));
	
	OOGL(glDrawArrays(GL_POINTS, 0, count));
	
	OOGL(glDisableClientState(GL_VERTEX_ARRAY));
	OOGL(glDisableClientState(GL_COLOR_ARRAY));
	OOGL(glDisable(GL_POINT_SPRITE));
	OOGL(glDisable(GL_TEXTURE_2D));
	
	OOGL(glBindBuffer(GL_ARRAY_BUFFER, 0));
	
	// Draw bad routes and height vectors.
	OOGLBEGIN(GL_LINES);
	for (NSUInteger i = 0; i < count; i++)
	{
		OOGESystem *system = [systems objectAtIndex:i];
		Vector p = system.position;
		for (NSUInteger j = i + 1; j < count; j++)
		{
			OOGESystem *other = [systems objectAtIndex:j];
			Vector q = other.position;
			if ([system hasNeighbour:other])
			{
				if (distance2(p, q) > (7 * 7))
				{
					glColor3f(1.0, 0.2, 0.0);
					glVertex3f(p.x, p.y, p.z);
					glVertex3f(q.x, q.y, q.z);
				}
			}
			else
			{
				if (distance2(p, q) <= (7 * 7))
				{
					glColor3f(0.8, 0.3, 0.3);
					glVertex3f(p.x, p.y, p.z);
					glVertex3f(q.x, q.y, q.z);
				}
			}
		}
		
		// Height vector.
		glColor3f(0.3, 0.1, 0.2);
		glVertex3f(p.x, p.y, p.z);
		glVertex3f(p.x, p.y, 0);
	}
	OOGLEND();
	
	if (self.drawForceVectors)
	{
		// Draw force vectors.
		OOGL(glColor3f(0, 0, 1.0));
		OOGLBEGIN(GL_LINES);
		for (OOGESystem *system in systems)
		{
			Vector p = system.position;
			Vector f = vector_add(p, system.force);
			
			glVertex3f(p.x, p.y, p.z);
			glVertex3f(f.x, f.y, f.z);
		}
		OOGLEND();
	}
}


-(void) makeTextureFromImage:(NSImage*)theImg forTexture:(GLuint*)texName
{
    NSBitmapImageRep* bitmap = [NSBitmapImageRep alloc];
    int samplesPerPixel = 0;
    NSSize imgSize = [theImg size];
	
    [theImg lockFocus];
    [bitmap initWithFocusedViewRect:NSMakeRect(0.0, 0.0, imgSize.width, imgSize.height)];
    [theImg unlockFocus];
	
    // Set proper unpacking row length for bitmap.
    glPixelStorei(GL_UNPACK_ROW_LENGTH, [bitmap pixelsWide]);
	
    // Set byte aligned unpacking (needed for 3 byte per pixel bitmaps).
    glPixelStorei (GL_UNPACK_ALIGNMENT, 1);
	
    // Generate a new texture name if one was not provided.
    if (*texName == 0)
        glGenTextures (1, texName);
    glBindTexture (GL_TEXTURE_2D, *texName);
	
    // Non-mipmap filtering (redundant for texture_rectangle).
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,  GL_LINEAR_MIPMAP_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_GENERATE_MIPMAP, GL_TRUE);
    samplesPerPixel = [bitmap samplesPerPixel];
	
    // Nonplanar, RGB 24 bit bitmap, or RGBA 32 bit bitmap.
    if(![bitmap isPlanar] && (samplesPerPixel == 3 || samplesPerPixel == 4)) {
		
        glTexImage2D(GL_TEXTURE_2D, 0,
					 samplesPerPixel == 4 ? GL_RGBA8 : GL_RGB8,
					 [bitmap pixelsWide],
					 [bitmap pixelsHigh],
					 0,
					 samplesPerPixel == 4 ? GL_RGBA : GL_RGB,
					 GL_UNSIGNED_BYTE,
					 [bitmap bitmapData]);
    } else {
        // Handle other bitmap formats.
    }
	
	
    // Clean up.
    [bitmap release];
}

@end


#if DRAW_AXES
static void DrawAxes(BOOL inLabels, float inScale)
{
	GLboolean oldLighting;
	glGetBooleanv(GL_LIGHTING, &oldLighting);
	if (oldLighting) glDisable(GL_LIGHTING);
	
	glScalef(inScale, inScale, inScale);
	
	glColor3f(1, 1, 1);
/*	glBegin(GL_POINTS);
	glVertex3f(0, 0, 0);
	glEnd();*/
	glBegin(GL_LINES);
	glColor3f(1, 0, 0);
	glVertex3f(0, 0, 0);
	glVertex3f(1, 0, 0);
	glVertex3f(1, 0, 0);
	glVertex3f(0.9, 0.05, 0);
	glVertex3f(1, 0, 0);
	glVertex3f(0.9, -0.05, 0);
	if (inLabels)
	{
		glVertex3f(1.1, 0.1, 0);
		glVertex3f(1.3, -0.1, 0);
		glVertex3f(1.1, -0.1, 0);
		glVertex3f(1.3, 0.1, 0);
	}
	
	glColor3f(0, 1, 0);
	glVertex3f(0, 0, 0);
	glVertex3f(0, 1, 0);
	glVertex3f(0, 1, 0);
	glVertex3f(0, 0.9, 0.05);
	glVertex3f(0, 1, 0);
	glVertex3f(0, 0.9, -0.05);
	if (inLabels)
	{
		glVertex3f(0, 1.1, 0.1);
		glVertex3f(0, 1.3, -0.1);
		glVertex3f(0, 1.2, -0.0);
		glVertex3f(0, 1.3, 0.1);
	}
	
	glColor3f(0, 0, 1);
	glVertex3f(0, 0, 0);
	glVertex3f(0, 0, 1);
	glVertex3f(0, 0, 1);
	glVertex3f(0.05, 0, 0.9);
	glVertex3f(0, 0, 1);
	glVertex3f(-0.05, 0, 0.9);
	if (inLabels)
	{
		glVertex3f(-0.1, 0, 1.1);
		glVertex3f(0.1, 0, 1.3);
		glVertex3f(0.1, 0, 1.1);
		glVertex3f(0.1, 0, 1.3);
		glVertex3f(-0.1, 0, 1.1);
		glVertex3f(-0.1, 0, 1.3);
	}
	glEnd();
	
	inScale = 1.0f / inScale;
	glScalef(inScale, inScale, inScale);
	
	if (oldLighting) glEnable(GL_LIGHTING);
}
#endif


#ifndef NDEBUG
static void CheckGLError(NSString *context)
{
	GLenum			errCode;
	const GLubyte	*errString = NULL;
	
	for (;;)
	{
		errCode = glGetError();
		if (errCode == GL_NO_ERROR)  break;
		
		errString = gluErrorString(errCode);
		OOLog(@"render.error", @"OpenGL error %s (%u) %@.", errString, errCode, context);
	}
}
#endif


static unsigned IntegerFromString(const GLubyte **ioString)
{
	if (EXPECT_NOT(ioString == NULL))  return 0;
	
	unsigned		result = 0;
	const GLubyte	*curr = *ioString;
	
	while ('0' <= *curr && *curr <= '9')
	{
		result = result * 10 + *curr++ - '0';
	}
	
	*ioString = curr;
	return result;
}


static void GetGLVersion(unsigned *major, unsigned *minor, unsigned *subminor)
{
	NSCParameterAssert(major != NULL && minor != NULL && subminor != NULL);
	
	*major = 0;
	*minor = 0;
	*subminor = 0;
	
	const GLubyte *version = glGetString(GL_VERSION);
	
	if (version != NULL)
	{
		*major = IntegerFromString(&version);
		if (*version == '.')
		{
			version++;
			*minor = IntegerFromString(&version);
		}
		if (*version == '.')
		{
			version++;
			*subminor = IntegerFromString(&version);
		}
	}
}