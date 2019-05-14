#ifndef OPT_H
#define OPT_H

struct options
{
	int hw;
	int output;
	int width;
	int height;
	int image;
	int loop;
	int nores;
};

void options_init();
void parseArgs(int argc, char *argv[], options *opt);

#endif
