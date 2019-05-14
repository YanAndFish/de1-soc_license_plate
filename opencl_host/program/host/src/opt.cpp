#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <iostream>
#include <assert.h>
#include <getopt.h>
#include "opt.h"

struct options opt;

void options_init()
{
    opt.hw = 1;
    opt.image = 0;
    opt.output = 0;
    opt.nores = 0;
    opt.width = 640;
    opt.height = 360;
    opt.loop = 100;
}

void parseArgs(int argc, char *argv[], options *opt)
{
    const char shortOptions[] = "w:h:l:m:i:o:n:";
    const struct option longOptions[] = {
        {"width", required_argument, NULL, 'w'},
        {"height", required_argument, NULL, 'h'},
        {"loop", required_argument, NULL, 'l'},
        {"image", required_argument, NULL, 'i'},
        {"output", required_argument, NULL, 'o'},
        {"nores", required_argument, NULL, 'n'},
        {0, 0, 0, 0}};
    int index;
    int c;

    for (;;)
    {
        c = getopt_long(argc, argv, shortOptions, longOptions, &index);

        if (c == -1)
        {
            break;
        }

        switch (c)
        {
        case 0:
            break;

        case 'h':
            opt->height = atoi(optarg);
            break;

        case 'w':
            opt->width = atoi(optarg);
            break;

        case 'l':
            opt->loop = atoi(optarg);
            break;
        case 'o':
            opt->output = atoi(optarg);
            break;
        case 'i':
            opt->image = 1;
            break;
        case 'n':
            opt->nores = 1;
            break;

            exit(EXIT_SUCCESS);
        default:
            exit(EXIT_FAILURE);
        }
    }
}
