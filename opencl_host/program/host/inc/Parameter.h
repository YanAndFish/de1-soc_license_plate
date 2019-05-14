#ifndef PARAMETER_H
#define PARAMETER_H

#define ON	1
#define OFF	0

//#define CAMERA_WIDTH opt.width
//#define CAMERA_HEIGHT opt.height

#define DEBUG  OFF

#define HW ON

struct HSVRange
{
	int HueMin = 0;
	int HueMax = 180;
	int SaturationMin = 0;
	int SaturationMax = 255;
	int ValueMin = 0;
	int ValueMax = 255;
};

struct MaskRectic
{
	int axis_x = 0;
	int axis_y = 0;
	int width  = 0;
	int height = 0;
};

struct MorphologyTimes
{
	int ErodeTimes  = 1;
	int DilateTimes = 1;
};

struct MaskWord
{
	int vertex_x = 0;
	int vertex_y = 0;
	int width = 0;
	int height = 0;
};

struct MatchResult_One
{
	char  ResultNumber = 200;
	double ResultMax = 1;
};
#endif // !__Parameter__

